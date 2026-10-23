# ---- Cluster ----

variable "cluster_name" {
  description = "kind cluster name."
  type        = string
  default     = "pong-gravitee"
}

variable "kind_node_image" {
  description = "kind node image. Sets the Kubernetes version."
  type        = string
  default     = "kindest/node:v1.31.4"
}

variable "gateway_host_port" {
  description = "Host port that reaches the gateway."
  type        = number
  default     = 8080

  validation {
    condition     = var.gateway_host_port >= 1024 && var.gateway_host_port <= 65535
    error_message = "gateway_host_port must be between 1024 and 65535."
  }
}

# ---- Namespaces ----

variable "gravitee_namespace" {
  description = "Namespace for MongoDB, the Management API, the gateway and GKO."
  type        = string
  default     = "gravitee"
}

variable "backend_namespace" {
  description = "Namespace for the pong backend."
  type        = string
  default     = "backend"
}

# ---- MongoDB ----

variable "mongodb" {
  description = "MongoDB for the Management API and gateway. Official image, authentication on, data on a PersistentVolumeClaim."
  type = object({
    image        = string
    database     = string
    username     = string
    storage_size = string
    resources = object({
      requests = object({ cpu = string, memory = string })
      limits   = object({ cpu = string, memory = string })
    })
  })
}

# ---- Gravitee APIM (Management API + Gateway) ----

variable "gravitee_chart_version" {
  description = "graviteeio/apim chart version."
  type        = string
  default     = "4.12.22"
}

variable "apim_values" {
  description = "Helm values for the graviteeio/apim release, passed through as given. Set in terraform.tfvars."
  type        = any

  validation {
    condition     = can(var.apim_values.gateway.service.nodePort) && can(var.apim_values.api.service.externalPort)
    error_message = "apim_values must set gateway.service.nodePort and api.service.externalPort."
  }

  validation {
    condition     = !can(var.apim_values.gateway.service.nodePort) || (var.apim_values.gateway.service.nodePort >= 30000 && var.apim_values.gateway.service.nodePort <= 32767)
    error_message = "gateway.service.nodePort must be in the Kubernetes NodePort range 30000-32767."
  }
}

variable "management_username" {
  description = "Management API user that GKO signs in with. Local default."
  type        = string
  default     = "admin"
}

variable "management_password" {
  description = "Management API password that GKO signs in with. Local default; override with TF_VAR_management_password."
  type        = string
  default     = "admin"
  sensitive   = true
}

# ---- GKO ----

variable "gko_chart_version" {
  description = "graviteeio/gko chart version."
  type        = string
  default     = "4.12.22"
}

variable "gko_values" {
  description = "Helm values for the graviteeio/gko release. Empty means chart defaults. Set in terraform.tfvars."
  type        = any
  default     = {}
}

variable "api_apply_delay" {
  description = "Wait before the /ping API is applied, so the Management API is ready. Runs on first install and whenever the apim or gko release inputs change."
  type        = string
  default     = "30s"
}

# ---- Backend ----

variable "backend_image" {
  description = "Python image for the pong backend."
  type        = string
  default     = "python:3.12.7-alpine3.20"
}

variable "backend_resources" {
  description = "Requests and limits for the backend pod."
  type = object({
    requests = object({ cpu = string, memory = string })
    limits   = object({ cpu = string, memory = string })
  })
  default = {
    requests = { cpu = "50m", memory = "32Mi" }
    limits   = { cpu = "250m", memory = "64Mi" }
  }
}
