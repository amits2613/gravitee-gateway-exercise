output "ping_url" {
  description = "URL of /ping through the gateway."
  value       = "http://localhost:${var.gateway_host_port}/ping"
}

output "kubeconfig_path" {
  description = "kubeconfig for kubectl."
  value       = kind_cluster.this.kubeconfig_path
}
