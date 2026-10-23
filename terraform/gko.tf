locals {
  # The chart names the Management API Service "<release>-apim-api".
  management_api_url = "http://${helm_release.apim.name}-apim-api.${kubernetes_namespace_v1.gravitee.metadata[0].name}.svc.cluster.local:${var.apim_values.api.service.externalPort}"
}

# GKO, installed with chart defaults as in the install-with-helm guide.
resource "helm_release" "gko" {
  name       = "graviteeio-gko"
  repository = "https://helm.gravitee.io"
  chart      = "gko"
  version    = var.gko_chart_version
  namespace  = kubernetes_namespace_v1.gravitee.metadata[0].name
  wait       = true
  timeout    = 300

  # Chart defaults when gko_values is empty.
  values = length(var.gko_values) > 0 ? [yamlencode(var.gko_values)] : []

  depends_on = [helm_release.apim]
}

# Tells GKO where the Management API is and how to sign in.
resource "kubectl_manifest" "management_context" {
  yaml_body = templatefile("${path.module}/gravitee/management-context.yaml.tftpl", {
    namespace               = kubernetes_namespace_v1.gravitee.metadata[0].name
    management_api_base_url = local.management_api_url
    management_username     = var.management_username
    management_password     = var.management_password
  })
  sensitive_fields = ["spec.auth.credentials.password"]

  depends_on = [helm_release.gko]
}

# GKO's admission webhook calls the Management API when an API is applied, so
# the Management API has to be answering first. The wait runs on first install
# and whenever the apim or gko release inputs change, which are the cases where
# the Management API can have restarted. It does not run when nothing changed,
# so a second apply shows no changes.
resource "time_sleep" "wait_for_management_api" {
  create_duration = var.api_apply_delay

  triggers = {
    apim_chart  = var.gravitee_chart_version
    apim_values = sha256(yamlencode(var.apim_values))
    gko_chart   = var.gko_chart_version
    gko_values  = sha256(yamlencode(var.gko_values))
  }

  depends_on = [kubectl_manifest.management_context]
}

# The /ping route, owned by the backend (backend/gravitee/pong-api.yaml).
# It is applied after the backend is rolled out, so the first request does not
# hit a missing backend.
resource "kubectl_manifest" "pong_api" {
  yaml_body = file("${path.module}/../backend/gravitee/pong-api.yaml")

  # On delete, wait for GKO's finalizer. Without this, the ManagementContext
  # delete is rejected while the API is still being removed.
  wait = true

  depends_on = [
    time_sleep.wait_for_management_api,
    kubernetes_deployment_v1.pong_backend,
  ]
}
