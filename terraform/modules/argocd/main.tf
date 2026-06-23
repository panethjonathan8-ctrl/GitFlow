# ── ArgoCD Namespace ──────────────────────────────────────────────────────────
resource "kubernetes_namespace" "argocd" {
  metadata {
    name = "argocd"

    labels = {
      "app.kubernetes.io/managed-by" = "terraform"
      Project                        = var.project
      Environment                    = var.env
    }
  }
}

# ── ArgoCD Helm Release ───────────────────────────────────────────────────────
resource "helm_release" "argocd" {
  name       = "argocd"
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-cd"
  version    = var.argocd_chart_version
  namespace  = kubernetes_namespace.argocd.metadata[0].name

  timeout = 600
  wait    = false
  # wait = false because ArgoCD has many components and Terraform's Helm provider
  # consistently times out waiting for them even when all pods are Running.
  # ArgoCD comes up reliably on its own — verified across multiple applies.
  # The argocd kubernetes_namespace resource below is what ensures the namespace
  # exists before any downstream resources reference it.

  values = [
    yamlencode({
      configs = {
        params = {
          # TLS is terminated at CloudFront — ArgoCD itself speaks plain HTTP.
          "server.insecure" = "true"
        }
        cm = {
          # Must match the public URL so Dex generates correct redirect URIs.
          url = "https://${var.argocd_hostname}"
        }
        secret = {
          # Injects dex.github.clientSecret into argocd-secret so the Dex
          # config below can reference it with $dex.github.clientSecret without
          # embedding the plaintext value in argocd-cm (a non-secret ConfigMap).
          extra = {
            "dex.github.clientSecret" = var.argocd_github_oauth_client_secret
          }
        }
        rbac = {
          # Only the allowed GitHub user gets admin. Everyone else gets role:''
          # which means no permissions — they see the login page but can't enter.
          "policy.csv"     = "g, ${var.argocd_github_allowed_user}, role:admin\n"
          "policy.default" = "role:''"
        }
      }

      server = {
        service = {
          # ClusterIP means the pod is only reachable inside the cluster.
          # The ALB Ingress below becomes the only public entry point.
          # This replaces the previous LoadBalancer (NLB) — saving ~$16/month.
          type = "ClusterIP"
        }
        ingress = {
          enabled          = true
          ingressClassName = "alb"
          annotations = {
            "alb.ingress.kubernetes.io/scheme"      = "internet-facing"
            "alb.ingress.kubernetes.io/target-type" = "ip"
            # Joins the shared ALB used by the app and Grafana.
            # One ALB serves all three hostnames — no extra load balancer cost.
            "alb.ingress.kubernetes.io/group.name"  = "gitflow-analyzer"
            "alb.ingress.kubernetes.io/group.order" = "15"
          }
          hosts = [var.argocd_hostname]
        }
      }
    }),

    # Dex connector config — written as raw YAML so the block scalar (|) is
    # preserved exactly as ArgoCD expects it in argocd-cm.
    # $dex.github.clientSecret is an ArgoCD substitution — at runtime ArgoCD
    # reads the value from argocd-secret and injects it here.
    <<-YAML
      configs:
        cm:
          dex.config: |
            connectors:
              - type: github
                id: github
                name: GitHub
                config:
                  clientID: ${var.argocd_github_oauth_client_id}
                  clientSecret: $dex.github.clientSecret
                  redirectURI: https://${var.argocd_hostname}/api/dex/callback
    YAML
  ]
}

# ── ArgoCD Application ────────────────────────────────────────────────────────
# The Application CRD is installed BY the ArgoCD Helm chart above.
# The Terraform Helm provider validates all resources against the Kubernetes API
# before applying, so we cannot embed the Application in extraObjects — it would
# fail because the CRD doesn't exist yet at validation time.
# Instead, we wait for ArgoCD to be ready, then apply the manifest with kubectl.
resource "null_resource" "argocd_application" {
  depends_on = [helm_release.argocd]

  triggers = {
    cluster_name = var.cluster_name
    aws_region   = var.aws_region
    # Re-runs if any Application manifest changes.
    # sha256(join(...)) combines all hashes into one trigger value.
    manifest_hash = sha256(join("", [
      filesha256("${path.root}/../../../k8s/argocd/application-dev.yaml"),
      filesha256("${path.root}/../../../k8s/argocd/application-staging.yaml"),
      filesha256("${path.root}/../../../k8s/argocd/application-production.yaml"),
      filesha256("${path.root}/../../../k8s/argocd/application-grafana-dashboards.yaml"),
    ]))
  }

  provisioner "local-exec" {
    command = <<-EOT
      aws eks update-kubeconfig --name "${var.cluster_name}" --region "${var.aws_region}"
      echo "Waiting for ArgoCD server to be ready..."
      kubectl wait --for=condition=available deployment/argocd-server \
        --namespace argocd --timeout=180s
      kubectl apply -f "${path.root}/../../../k8s/argocd/application-dev.yaml"
      kubectl apply -f "${path.root}/../../../k8s/argocd/application-staging.yaml"
      kubectl apply -f "${path.root}/../../../k8s/argocd/application-production.yaml"
      kubectl apply -f "${path.root}/../../../k8s/argocd/application-grafana-dashboards.yaml"
      kubectl delete application gitflow-analyzer -n argocd --ignore-not-found=true 2>/dev/null || true
      echo "ArgoCD Applications registered — syncs will begin within ~3 minutes"
    EOT
  }

  # Runs during terraform destroy BEFORE the ArgoCD Helm release is deleted.
  # Without this the ArgoCD app controller is gone before Application objects
  # are cleaned up, leaving their finalizers stuck and namespaces permanently
  # in Terminating. The || true on each command ensures a missing cluster or
  # already-deleted Application never blocks the destroy.
  provisioner "local-exec" {
    when    = destroy
    command = <<-EOT
      aws eks update-kubeconfig --name "${self.triggers.cluster_name}" --region "${self.triggers.aws_region}" || true
      for app in gitflow-analyzer-dev gitflow-analyzer-staging gitflow-analyzer-production grafana-dashboards gitflow-analyzer; do
        kubectl patch application "$app" -n argocd \
          -p '{"metadata":{"finalizers":[]}}' --type=merge 2>/dev/null || true
        kubectl delete application "$app" -n argocd --ignore-not-found=true 2>/dev/null || true
      done
      echo "ArgoCD Application finalizers cleared"
    EOT
  }
}
