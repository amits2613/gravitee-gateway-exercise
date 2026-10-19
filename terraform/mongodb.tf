# MongoDB, the Management API's repository. All Helm values come from
# mongodb_values in terraform.tfvars.
resource "helm_release" "mongodb" {
  name            = "gravitee-mongodb"
  repository      = "https://charts.bitnami.com/bitnami"
  chart           = "mongodb"
  version         = var.mongodb_chart_version == "" ? null : var.mongodb_chart_version
  namespace       = kubernetes_namespace_v1.gravitee.metadata[0].name
  wait            = true
  timeout         = 600

  values = [yamlencode(var.mongodb_values)]
}
