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
    # Re-runs if any of the three Application manifests change.
    # sha256(join(...)) combines all three hashes into one trigger value.
    manifest_hash = sha256(join("", [
      filesha256("${path.root}/../../../k8s/argocd/application-dev.yaml"),
      filesha256("${path.root}/../../../k8s/argocd/application-staging.yaml"),
      filesha256("${path.root}/../../../k8s/argocd/application-production.yaml"),
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
      for app in gitflow-analyzer-dev gitflow-analyzer-staging gitflow-analyzer-production gitflow-analyzer; do
        kubectl patch application "$app" -n argocd \
          -p '{"metadata":{"finalizers":[]}}' --type=merge 2>/dev/null || true
        kubectl delete application "$app" -n argocd --ignore-not-found=true 2>/dev/null || true
      done
      echo "ArgoCD Application finalizers cleared"
    EOT
  }
}
