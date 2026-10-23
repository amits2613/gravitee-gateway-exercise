# The one file to edit. Helm values for the apim and gko releases are set here
# and passed through unchanged.

cluster_name    = "pong-gravitee"
kind_node_image = "kindest/node:v1.31.4"

gateway_host_port = 8080 # host port -> gateway.service.nodePort below

gravitee_namespace = "gravitee"
backend_namespace  = "backend"

api_apply_delay = "30s"

backend_image = "python:3.12.7-alpine3.20"

# ---- graviteeio/apim release ----
gravitee_chart_version = "4.12.22"

apim_values = {
  ui            = { enabled = false }
  portal        = { enabled = false }
  mongodb       = { enabled = false } # standalone release in mongodb.tf
  elasticsearch = { enabled = false }
  es            = { enabled = false }

  # Placeholder without credentials. The real connection string, with the
  # generated password, comes from the Secret through api.env and gateway.env.
  mongo = {
    uri = "mongodb://gravitee-mongodb.gravitee.svc.cluster.local:27017/gravitee"
  }

  management = { type = "mongodb" }
  ratelimit  = { type = "mongodb" }

  api = {
    enabled      = true
    replicaCount = 1
    image = {
      repository = "graviteeio/apim-management-api"
      tag        = "4.12.22"
      pullPolicy = "IfNotPresent"
    }
    service = {
      type         = "ClusterIP"
      externalPort = 83 # GKO connects to this port
      internalPort = 8083
    }
    ingress = {
      management = { enabled = false }
      portal     = { enabled = false }
    }
    resources = {
      requests = { cpu = "250m", memory = "512Mi" }
      limits   = { cpu = "1", memory = "1Gi" }
    }
    analytics = { type = "none" }

    # Overrides management.mongodb.uri with the value from the Secret created in mongodb.tf
    env = [
      {
        name = "gravitee_management_mongodb_uri"
        valueFrom = {
          secretKeyRef = { name = "gravitee-mongodb-uri", key = "uri" }
        }
      },
    ]
  }

  gateway = {
    enabled      = true
    replicaCount = 1
    image = {
      repository = "graviteeio/apim-gateway"
      tag        = "4.12.22"
      pullPolicy = "IfNotPresent"
    }
    service = {
      type         = "NodePort"
      externalPort = 8082
      internalPort = 8082
      nodePort     = 30082 # kind maps gateway_host_port to this port
    }
    ingress = { enabled = false }
    resources = {
      requests = { cpu = "250m", memory = "512Mi" }
      limits   = { cpu = "1", memory = "1Gi" }
    }
    reporters = { elasticsearch = { enabled = false } }

    # Prometheus metrics on the gateway technical API (port 18082)
    services = {
      metrics = {
        enabled    = true
        prometheus = { enabled = true }
      }
    }

    # Overrides the MongoDB connection for the management and rate-limit repositories
    env = [
      {
        name = "gravitee_management_mongodb_uri"
        valueFrom = {
          secretKeyRef = { name = "gravitee-mongodb-uri", key = "uri" }
        }
      },
      {
        name = "gravitee_ratelimit_mongodb_uri"
        valueFrom = {
          secretKeyRef = { name = "gravitee-mongodb-uri", key = "uri" }
        }
      },
    ]
  }
}

# ---- graviteeio/gko release ----
gko_chart_version = "4.12.22"

# Empty means chart defaults, as in the install-with-helm guide.
gko_values = {}

# ---- MongoDB (mongodb.tf) ----
# Official image with a fixed tag. The Bitnami image on Docker Hub only has a
# floating "latest" tag, so it cannot be pinned.
mongodb = {
  image        = "mongo:7.0.30-jammy"
  database     = "gravitee"
  username     = "gravitee"
  storage_size = "1Gi"
  resources = {
    requests = { cpu = "250m", memory = "512Mi" }
    limits   = { cpu = "1", memory = "1Gi" }
  }
}
