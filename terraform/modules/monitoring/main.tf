locals {
  # Alloy uses the River configuration language.
  # This single config handles both log collection (→ Loki) and
  # trace reception (→ Tempo) so we only need one agent DaemonSet.
  alloy_config = <<-EOT
    // ── Pod log collection ──────────────────────────────────────────────────────
    // Discovers every pod on this node and ships stdout/stderr to Loki.
    discovery.kubernetes "pods" {
      role = "pod"
    }

    discovery.relabel "pod_logs" {
      targets = discovery.kubernetes.pods.targets

      rule {
        source_labels = ["__meta_kubernetes_namespace"]
        target_label  = "namespace"
      }
      rule {
        source_labels = ["__meta_kubernetes_pod_name"]
        target_label  = "pod"
      }
      rule {
        source_labels = ["__meta_kubernetes_container_name"]
        target_label  = "container"
      }
      rule {
        source_labels = ["__meta_kubernetes_pod_label_app_kubernetes_io_name"]
        target_label  = "app"
      }
    }

    loki.source.kubernetes "pods" {
      targets    = discovery.relabel.pod_logs.output
      forward_to = [loki.write.default.receiver]
    }

    loki.write "default" {
      endpoint {
        url = "http://loki.monitoring.svc.cluster.local:3100/loki/api/v1/push"
      }
    }

    // ── Trace reception ─────────────────────────────────────────────────────────
    // Listens for OTLP traces from the Flask services on gRPC (4317) and
    // HTTP (4318), then forwards them to Tempo.
    otelcol.receiver.otlp "default" {
      grpc {
        endpoint = "0.0.0.0:4317"
      }
      http {
        endpoint = "0.0.0.0:4318"
      }
      output {
        traces = [otelcol.exporter.otlp.tempo.input]
      }
    }

    otelcol.exporter.otlp "tempo" {
      client {
        endpoint = "tempo.monitoring.svc.cluster.local:4317"
        tls {
          insecure = true
        }
      }
    }
  EOT
}

resource "kubernetes_namespace" "monitoring" {
  metadata {
    name = "monitoring"
    labels = {
      Project                        = var.project
      Environment                    = var.env
      "app.kubernetes.io/managed-by" = "terraform"
    }
  }
}

# ── Grafana GitHub OAuth secret ───────────────────────────────────────────────
# The client secret must not appear in the Helm values (those end up in
# Terraform state in plain text). Instead we store it in a Kubernetes Secret
# and tell Grafana to read it from the environment via envFromSecret.
# The secret key name starts with GF_ so Grafana's env-var config system
# picks it up automatically via $__env{} in grafana.ini.
resource "kubernetes_secret" "grafana_github_oauth" {
  metadata {
    name      = "grafana-github-oauth"
    namespace = kubernetes_namespace.monitoring.metadata[0].name
  }

  data = {
    GF_AUTH_GITHUB_CLIENT_SECRET = var.github_oauth_client_secret
  }

  depends_on = [kubernetes_namespace.monitoring]
}

# ── Prometheus + Grafana + AlertManager ───────────────────────────────────────
resource "helm_release" "kube_prometheus_stack" {
  name       = "monitoring"
  repository = "https://prometheus-community.github.io/helm-charts"
  chart      = "kube-prometheus-stack"
  version    = var.chart_version
  namespace  = kubernetes_namespace.monitoring.metadata[0].name

  timeout = 600

  values = [
    yamlencode({
      # ── Prometheus ──────────────────────────────────────────────────────────
      prometheus = {
        prometheusSpec = {
          retention = var.prometheus_retention

          resources = {
            requests = { cpu = "200m", memory = "512Mi" }
            limits   = { cpu = "500m", memory = "1Gi" }
          }

          storageSpec = {
            volumeClaimTemplate = {
              spec = {
                storageClassName = "gp2"
                accessModes      = ["ReadWriteOnce"]
                resources = {
                  requests = { storage = var.prometheus_storage_size }
                }
              }
            }
          }
        }
      }

      # ── Grafana ─────────────────────────────────────────────────────────────
      grafana = {
        adminPassword = var.grafana_admin_password

        # Load the OAuth client secret from the kubernetes_secret we created
        # above. Every key in that secret becomes an env var in the Grafana pod.
        # grafana.ini below references the secret via $__env{} syntax.
        envFromSecret = "grafana-github-oauth"

        resources = {
          requests = { cpu = "100m", memory = "192Mi" }
          limits   = { cpu = "200m", memory = "512Mi" }
          # 512Mi limit: Grafana with Prometheus + Loki + Tempo data sources and
          # custom dashboards sits at ~240Mi at rest. 512Mi gives safe headroom
          # for dashboard rendering spikes without risking OOMKill.
        }

        persistence = { enabled = false }

        # Grafana Ingress — joins the shared ALB IngressGroup so Grafana is
        # reachable at https://gitflow.space/dashboard.
        # group.order 10 means Grafana path rules are checked BEFORE the
        # gitflow-analyzer rules (order 20), preventing /dashboard requests
        # from accidentally matching the app's catch-all routes.
        ingress = {
          enabled           = true
          ingressClassName  = "alb"
          annotations = {
            "alb.ingress.kubernetes.io/scheme"       = "internet-facing"
            "alb.ingress.kubernetes.io/target-type"  = "ip"
            "alb.ingress.kubernetes.io/group.name"   = "gitflow-analyzer"
            "alb.ingress.kubernetes.io/group.order"  = "10"
          }
          path     = "/dashboard"
          pathType = "Prefix"
          # No hosts entry — ALB route matching is path-only.
          # CloudFront sends requests with the ALB hostname in Host (due to
          # AllViewerExceptHostHeader policy), not gitflow.space.
          hosts = []
        }

        # grafana.ini is Grafana's main config file.
        # kube-prometheus-stack merges these keys into the config on startup.
        "grafana.ini" = {
          server = {
            # Tell Grafana it lives at /dashboard so all generated links
            # (OAuth callback, redirect after login, asset URLs) use the right
            # path. Without this, Grafana generates links without the prefix
            # and the browser gets 404s from CloudFront.
            root_url          = "https://www.gitflow.space/dashboard"
            serve_from_sub_path = true
          }

          auth = {
            # Disable the username/password login form completely.
            # The only way to log in is via GitHub OAuth.
            # This means if OAuth ever breaks, you can re-enable it by setting
            # this back to false and running terraform apply.
            disable_login_form = true
          }

          "auth.github" = {
            enabled       = true
            client_id     = var.github_oauth_client_id
            # The secret is never written to this file — it is read from the
            # GF_AUTH_GITHUB_CLIENT_SECRET env var at runtime.
            client_secret = "$__env{GF_AUTH_GITHUB_CLIENT_SECRET}"
            scopes        = "user:email,read:org"
            # read:org is required so GitHub returns an empty teams list
            # instead of 404 for personal accounts. Without it Grafana's
            # teams fetch fails and the login is rejected before allowed_users
            # is even checked.
            auth_url      = "https://github.com/login/oauth/authorize"
            token_url     = "https://github.com/login/oauth/access_token"
            api_url       = "https://api.github.com/user"
            # allowed_users is a comma-separated whitelist of GitHub usernames.
            # Only the listed user(s) can complete the OAuth flow. Everyone else
            # sees "Login failed" even with a valid GitHub account.
            allowed_users        = var.github_oauth_allowed_user
            allow_sign_up        = true
            # allow_sign_up=true lets allowed users create their Grafana account
            # on first login. Security is enforced by allowed_users above —
            # only panethjonathan8-ctrl can get through GitHub OAuth.
            skip_org_role_sync   = true
            # skip_org_role_sync: Grafana normally fetches GitHub team memberships
            # to map org roles → Grafana roles. That call requires read:org scope.
            # Since we only use allowed_users (not allowed_organizations or team_ids),
            # we don't need org syncing — disabling it avoids the 404 from GitHub.
          }
        }

        # Data sources are provisioned automatically on every Grafana start.
        # Adding them here means no manual setup in the UI after a cluster rebuild.
        additionalDataSources = [
          {
            name      = "Loki"
            type      = "loki"
            uid       = "loki"
            # Explicit UID so the Tempo trace-to-logs link always resolves
            # correctly, even after a cluster rebuild.
            url       = "http://loki.monitoring.svc.cluster.local:3100"
            access    = "proxy"
            isDefault = false
          },
          {
            name      = "Tempo"
            type      = "tempo"
            uid       = "tempo"
            url       = "http://tempo.monitoring.svc.cluster.local:3100"
            access    = "proxy"
            isDefault = false
            jsonData = {
              httpMethod = "GET"
              # Click a trace span in Tempo and Grafana jumps straight to
              # the matching log lines in Loki for that trace ID.
              tracesToLogsV2 = {
                datasourceUid  = "loki"
                filterByTraceID = true
              }
              # Pulls service graph metrics from Prometheus once OTel
              # instrumentation is added (step 2).
              serviceMap = {
                datasourceUid = "prometheus"
              }
              nodeGraph = {
                enabled = true
              }
            }
          }
        ]
      }

      # ── AlertManager ────────────────────────────────────────────────────────
      alertmanager = {
        alertmanagerSpec = {
          resources = {
            requests = { cpu = "50m", memory = "64Mi" }
            limits   = { cpu = "100m", memory = "128Mi" }
          }
        }
      }

      # ── Node Exporter ────────────────────────────────────────────────────────
      "prometheus-node-exporter" = {
        resources = {
          requests = { cpu = "50m", memory = "32Mi" }
          limits   = { cpu = "100m", memory = "64Mi" }
        }
      }

      # ── kube-state-metrics ───────────────────────────────────────────────────
      "kube-state-metrics" = {
        resources = {
          requests = { cpu = "50m", memory = "64Mi" }
          limits   = { cpu = "100m", memory = "128Mi" }
        }
      }
    })
  ]

  depends_on = [kubernetes_namespace.monitoring, kubernetes_secret.grafana_github_oauth]
  # Wait for the OAuth secret to exist before Helm deploys Grafana — the pod
  # will fail to start if it tries to read an envFromSecret that doesn't exist.
}

# ── Loki ─────────────────────────────────────────────────────────────────────
# Single binary mode: all Loki components in one pod. Right-sized for dev —
# no replication, filesystem storage backed by a single EBS volume.
resource "helm_release" "loki" {
  name       = "loki"
  repository = "https://grafana.github.io/helm-charts"
  chart      = "loki"
  version    = var.loki_chart_version
  namespace  = kubernetes_namespace.monitoring.metadata[0].name

  timeout = 300

  values = [
    yamlencode({
      deploymentMode = "SingleBinary"

      loki = {
        auth_enabled = false
        # auth_enabled: false — no multi-tenant setup needed for dev.
        # Every log query returns results across all namespaces.

        commonConfig = {
          replication_factor = 1
        }

        storage = {
          type = "filesystem"
          # Stores log chunks directly on the EBS volume.
          # No S3 or object storage needed for a dev environment.
        }

        # Loki 6.x requires an explicit schema_config — it no longer ships
        # a default. v13 with tsdb is the current recommended schema.
        schemaConfig = {
          configs = [
            {
              from         = "2024-01-01"
              store        = "tsdb"
              object_store = "filesystem"
              schema       = "v13"
              index = {
                prefix = "index_"
                period = "24h"
              }
            }
          ]
        }
      }

      singleBinary = {
        replicas = 1
        persistence = {
          enabled      = true
          size         = var.loki_storage_size
          storageClass = "gp2"
        }
        resources = {
          requests = { cpu = "100m", memory = "256Mi" }
          limits   = { cpu = "200m", memory = "512Mi" }
        }
      }

      # Disable the read/write/backend components used in scalable mode.
      read    = { replicas = 0 }
      write   = { replicas = 0 }
      backend = { replicas = 0 }

      # The gateway is an nginx proxy in front of Loki — not needed when
      # everything is in the same cluster talking directly to the service.
      gateway = { enabled = false }

      # Memcached caches — disabled for dev to avoid extra Pending pods.
      # In production these would reduce Loki query latency significantly.
      chunksCache  = { enabled = false }
      resultsCache = { enabled = false }
    })
  ]

  depends_on = [kubernetes_namespace.monitoring]
}

# ── Tempo ─────────────────────────────────────────────────────────────────────
# Single binary mode: all Tempo components in one pod.
# Receives traces on port 4317 (gRPC OTLP) from Alloy.
# Serves trace queries to Grafana on port 3100.
resource "helm_release" "tempo" {
  name       = "tempo"
  repository = "https://grafana.github.io/helm-charts"
  chart      = "tempo"
  version    = var.tempo_chart_version
  namespace  = kubernetes_namespace.monitoring.metadata[0].name

  timeout = 300

  values = [
    yamlencode({
      tempo = {
        storage = {
          trace = {
            backend = "local"
            local = {
              path = "/var/tempo/traces"
            }
          }
        }
      }

      persistence = {
        enabled           = true
        size              = var.tempo_storage_size
        storageClassName  = "gp2"
      }

      resources = {
        requests = { cpu = "100m", memory = "256Mi" }
        limits   = { cpu = "200m", memory = "512Mi" }
      }
    })
  ]

  depends_on = [kubernetes_namespace.monitoring]
}

# ── Grafana Alloy ─────────────────────────────────────────────────────────────
# DaemonSet — one pod per node.
# Does two jobs: ships pod logs to Loki and receives OTLP traces → Tempo.
# Replaces both Promtail (log agent) and a standalone OTel Collector.
resource "helm_release" "alloy" {
  name       = "alloy"
  repository = "https://grafana.github.io/helm-charts"
  chart      = "alloy"
  version    = var.alloy_chart_version
  namespace  = kubernetes_namespace.monitoring.metadata[0].name

  timeout = 300

  values = [
    yamlencode({
      alloy = {
        configMap = {
          content = local.alloy_config
        }

        # Expose OTLP ports so Flask services can send traces to Alloy.
        # gRPC on 4317, HTTP on 4318 — we use HTTP from the Python OTel SDK.
        extraPorts = [
          {
            name       = "otlp-grpc"
            port       = 4317
            targetPort = 4317
            protocol   = "TCP"
          },
          {
            name       = "otlp-http"
            port       = 4318
            targetPort = 4318
            protocol   = "TCP"
          }
        ]
      }

      controller = {
        type = "daemonset"
        # DaemonSet ensures one Alloy pod runs on every node.
        # This is required for loki.source.kubernetes — the component
        # reads log files from the node's filesystem, so it must run
        # on the same node as the pods whose logs it is collecting.
      }

      resources = {
        requests = { cpu = "50m", memory = "128Mi" }
        limits   = { cpu = "200m", memory = "256Mi" }
      }
    })
  ]

  depends_on = [helm_release.loki, helm_release.tempo]
  # Wait for Loki and Tempo to be up before Alloy starts trying to push to them.
}

# ── Metrics Server ───────────────────────────────────────────────────────────
# Required for HPA to read CPU and memory usage from pods.
# Without this, HPA cannot get metrics and will never scale.
# EKS does not install Metrics Server by default — it must be added manually.
resource "helm_release" "metrics_server" {
  name       = "metrics-server"
  repository = "https://kubernetes-sigs.github.io/metrics-server/"
  chart      = "metrics-server"
  version    = "3.12.1"
  namespace  = "kube-system"

  values = [yamlencode({
    args = ["--kubelet-insecure-tls"]
    # EKS node kubelets use a self-signed certificate. This flag tells
    # Metrics Server not to verify it — safe inside the cluster VPC.
  })]
}

# ── Grafana Dashboard ─────────────────────────────────────────────────────────
# The kube-prometheus-stack sidecar watches for ConfigMaps labelled
# grafana_dashboard="1" in the monitoring namespace and hot-loads them into
# Grafana automatically — no pod restart needed.
resource "kubernetes_config_map" "grafana_dashboard_app" {
  metadata {
    name      = "gitflow-app-dashboard"
    namespace = kubernetes_namespace.monitoring.metadata[0].name
    labels = {
      grafana_dashboard = "1"
    }
  }

  data = {
    "gitflow-app.json" = file("${path.module}/dashboards/gitflow-app.json")
  }

  depends_on = [helm_release.kube_prometheus_stack]
}
