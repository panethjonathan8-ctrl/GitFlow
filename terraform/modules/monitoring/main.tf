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

resource "helm_release" "kube_prometheus_stack" {
  name       = "monitoring"
  repository = "https://prometheus-community.github.io/helm-charts"
  chart      = "kube-prometheus-stack"
  version    = var.chart_version
  namespace  = kubernetes_namespace.monitoring.metadata[0].name

  timeout = 600
  # kube-prometheus-stack installs many CRDs and controllers.
  # The default 300s timeout is sometimes not enough on a fresh cluster.

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
                # gp2 is the default EBS storage class that ships with EKS.
                # It provisions an SSD-backed EBS volume in the same AZ as the pod.
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

        resources = {
          requests = { cpu = "100m", memory = "128Mi" }
          limits   = { cpu = "200m", memory = "256Mi" }
        }

        # Grafana dashboards are auto-provisioned from ConfigMaps on every start.
        # No persistent disk needed — dashboards come back automatically.
        persistence = { enabled = false }
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
      # Runs as a DaemonSet — one pod per node. Exposes CPU, RAM, disk, network
      # metrics for the underlying EC2 instance. Very lightweight.
      "prometheus-node-exporter" = {
        resources = {
          requests = { cpu = "50m", memory = "32Mi" }
          limits   = { cpu = "100m", memory = "64Mi" }
        }
      }

      # ── kube-state-metrics ───────────────────────────────────────────────────
      # Watches Kubernetes objects (Deployments, Pods, etc.) and exposes metrics
      # like pod restart count, deployment replica status, resource requests vs
      # limits. This is where "how many times did my pod crash?" comes from.
      "kube-state-metrics" = {
        resources = {
          requests = { cpu = "50m", memory = "64Mi" }
          limits   = { cpu = "100m", memory = "128Mi" }
        }
      }
    })
  ]

  depends_on = [kubernetes_namespace.monitoring]
}
