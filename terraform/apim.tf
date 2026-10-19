# Gravitee API Management, Community Edition. All Helm values come from
# apim_values in terraform.tfvars. The chart puts a checksum of its ConfigMap
# on each pod, so pods restart when the values change.
resource "helm_release" "apim" {
  name            = "gravitee"
  repository      = "https://helm.gravitee.io"
  chart           = "apim"
  version         = var.gravitee_chart_version
  namespace       = kubernetes_namespace_v1.gravitee.metadata[0].name
  wait            = true
  timeout         = 900
  upgrade_install = true

  values = [yamlencode(var.apim_values)]

  depends_on = [helm_release.mongodb]
}
