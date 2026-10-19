locals {
  # The chart names the Management API Service "<release>-apim-api".
  management_api_url = "http://${helm_release.apim.name}-apim-api.${kubernetes_namespace_v1.gravitee.metadata[0].name}.svc.cluster.local:${var.apim_values.api.service.externalPort}"
}

# GKO, installed with chart defaults as in the install-with-helm guide.
resource "helm_release" "gko" {
  name            = "graviteeio-gko"
  repository      = "https://helm.gravitee.io"
  chart           = "gko"
  version         = var.gko_chart_version
  namespace       = kubernetes_namespace_v1.gravitee.metadata[0].name
  wait            = true
  timeout         = 300
  upgrade_install = true

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
# the API has to be up first. timestamp() makes this wait run on every apply.
resource "time_sleep" "wait_for_management_api" {
  create_duration = var.api_apply_delay

  triggers = {
    run_at = timestamp()
  }

  depends_on = [kubectl_manifest.management_context]
}

# The /ping route, owned by the backend (backend/gravitee/pong-api.yaml).
# resource "kubectl_manifest" "pong_api" {
#   yaml_body = file("${path.module}/../backend/gravitee/pong-api.yaml")

#   depends_on = [time_sleep.wait_for_management_api]
# }

# # Destroy pong_api before management_context, so the webhook is satisfied.
# resource "null_resource" "destroy_order" {
#   triggers = {
#     management_context_id = kubectl_manifest.management_context.id
#   }

#   depends_on = [kubectl_manifest.pong_api]
# }

resource "kubectl_manifest" "pong_api" {
  yaml_body = file("${path.module}/../backend/gravitee/pong-api.yaml")

  depends_on = [time_sleep.wait_for_management_api]
  wait = true
}