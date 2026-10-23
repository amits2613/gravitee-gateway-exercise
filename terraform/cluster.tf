# Local cluster. The gateway NodePort (apim_values) is mapped to a host port, so
# http://localhost:<gateway_host_port>/ping works without an ingress controller.
resource "kind_cluster" "this" {
  name            = var.cluster_name
  node_image      = var.kind_node_image
  wait_for_ready  = true
  kubeconfig_path = "${path.module}/.kube/${var.cluster_name}.kubeconfig"

  kind_config {
    kind        = "Cluster"
    api_version = "kind.x-k8s.io/v1alpha4"

    node {
      role = "control-plane"

      extra_port_mappings {
        container_port = var.apim_values.gateway.service.nodePort
        host_port      = var.gateway_host_port
        listen_address = "127.0.0.1"
        protocol       = "TCP"
      }
    }
  }
}

resource "kubernetes_namespace_v1" "gravitee" {
  metadata {
    name = var.gravitee_namespace
    labels = {
      "app.kubernetes.io/part-of" = var.cluster_name
      # Third-party charts run here. Violations of the restricted level are
      # logged, not blocked.
      "pod-security.kubernetes.io/audit" = "restricted"
    }
  }
  depends_on = [kind_cluster.this]
}

resource "kubernetes_namespace_v1" "backend" {
  metadata {
    name = var.backend_namespace
    labels = {
      "app.kubernetes.io/part-of"          = var.cluster_name
      "pod-security.kubernetes.io/enforce" = "restricted"
    }
  }
  depends_on = [kind_cluster.this]
}
