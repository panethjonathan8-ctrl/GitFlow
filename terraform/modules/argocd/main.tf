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
