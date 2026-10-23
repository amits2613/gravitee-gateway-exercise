# Pong backend. The source is mounted from a ConfigMap. Its hash is set on the
# pod, so the pod restarts when backend/app.py changes.
locals {
  backend_src = file("${path.module}/../backend/app.py")
}

resource "kubernetes_config_map_v1" "pong_backend" {
  metadata {
    name      = "pong-backend-src"
    namespace = kubernetes_namespace_v1.backend.metadata[0].name
  }
  data = { "app.py" = local.backend_src }
}

resource "kubernetes_deployment_v1" "pong_backend" {
  metadata {
    name      = "pong-backend"
    namespace = kubernetes_namespace_v1.backend.metadata[0].name
    labels    = { app = "pong-backend" }
  }

  spec {
    replicas = 1

    selector {
      match_labels = { app = "pong-backend" }
    }

    template {
      metadata {
        labels      = { app = "pong-backend" }
        annotations = { "checksum/app-py" = sha256(local.backend_src) }
      }

      spec {
        automount_service_account_token  = false
        termination_grace_period_seconds = 10

        security_context {
          run_as_non_root = true
          run_as_user     = 65534
          seccomp_profile {
            type = "RuntimeDefault"
          }
        }

        container {
          name              = "pong"
          image             = var.backend_image
          image_pull_policy = "IfNotPresent"
          command           = ["python", "/app/app.py"]

          env {
            name  = "PYTHONDONTWRITEBYTECODE"
            value = "1"
          }

          port {
            name           = "http"
            container_port = 8080
          }

          volume_mount {
            name       = "src"
            mount_path = "/app"
            read_only  = true
          }

          resources {
            requests = var.backend_resources.requests
            limits   = var.backend_resources.limits
          }

          readiness_probe {
            http_get {
              path = "/healthz"
              port = "http"
            }
            initial_delay_seconds = 2
            period_seconds        = 5
          }

          liveness_probe {
            http_get {
              path = "/healthz"
              port = "http"
            }
            initial_delay_seconds = 10
            period_seconds        = 20
          }

          security_context {
            allow_privilege_escalation = false
            read_only_root_filesystem  = true
            capabilities {
              drop = ["ALL"]
            }
          }
        }

        volume {
          name = "src"
          config_map {
            name = kubernetes_config_map_v1.pong_backend.metadata[0].name
          }
        }
      }
    }
  }
}

resource "kubernetes_service_v1" "pong_backend" {
  metadata {
    name      = "pong-backend"
    namespace = kubernetes_namespace_v1.backend.metadata[0].name
  }

  spec {
    type     = "ClusterIP"
    selector = { app = "pong-backend" }

    port {
      name        = "http"
      port        = 8080
      target_port = 8080
    }
  }
}
