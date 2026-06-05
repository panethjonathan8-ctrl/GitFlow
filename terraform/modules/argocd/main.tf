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
  # ArgoCD deploys ~10 components (server, repo-server, application-controller,
  # dex, redis, etc.). 10 minutes gives them all time to become Ready.

  wait = true
  # Don't return until all pods are Running — this ensures any subsequent
  # resources applied after this module don't run against a half-ready ArgoCD.

  values = [
    yamlencode({
      configs = {
        params = {
          "server.insecure" = "true"
          # Disables TLS on the ArgoCD server process itself.
          # Fine for dev — TLS would be terminated at the Load Balancer or
          # an Ingress in a production setup with a real domain.
        }
      }

      server = {
        service = {
          type = "LoadBalancer"
          # Creates an AWS NLB that gives the ArgoCD UI a public IP.
          # Cost: ~$16/month while the cluster is running.
          # In production: use ClusterIP here and put an Ingress in front
          # so you get TLS, a proper hostname, and auth at the edge.
        }
      }
    })
  ]
}
