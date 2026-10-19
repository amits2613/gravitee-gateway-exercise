# pong-gravitee

Gravitee API Management (Community Edition) on a local kind cluster.

`GET /ping` through the gateway returns `pong`.

## Prerequisites

| Tool | Install |
|---|---|
| **Docker** (running) | [Docker Desktop](https://www.docker.com/products/docker-desktop) (Windows/macOS), [Docker Engine](https://docs.docker.com/engine/install/) (Linux) |
| **Terraform** 1.6+ | [terraform.io](https://www.terraform.io/downloads) |
| **Python** 3.9+ | [python.org](https://www.python.org/) |

Docker needs ~4 CPUs and 6 GB memory. Host port 8080 must be free.

## Architecture Flow

```
curl localhost:8080/ping
   ↓
kind port mapping (8080 → node port 30082)
   ↓
Gateway Service (NodePort) → Gateway pod
   ↓
pong-backend Service → pong-backend pod
   ↓
"pong"

Setup:
Terraform → applies ApiV4Definition (pong-api.yaml)
         → GKO → ManagementContext → Management API → MongoDB
         → Gateway picks up the API
```

## Quick Start

Windows (PowerShell):
```powershell
python run.py up
curl.exe http://localhost:8080/ping
python run.py down
```

macOS / Linux:
```bash
python3 run.py up
curl http://localhost:8080/ping
python3 run.py down
```

- `up` creates the cluster and deploys everything. Exits once `/ping` returns `pong`.
- `down` removes everything.

The cluster keeps running until `down`. Use the URL in a browser, or run `python run.py test` to verify.

## Configuration

Edit `terraform/terraform.tfvars` to change:
- Ports: `gateway_host_port` (default 8080)
- Versions: `gravitee_chart_version`, `gko_chart_version`, image tags
- Helm values: `apim_values`, `gko_values`, `mongodb_values`

Every change is safe to re-apply. Terraform handles state.

## What Each Command Does

| Command | Action |
|---|---|
| `python run.py up` | `terraform init`, `terraform apply`, wait for `/ping`, exit |
| `python run.py test` | Call `/ping`, pass only if body is `pong` |
| `python run.py down` | `terraform destroy` |

## File Structure

```
run.py                          entrypoint (up / test / down)
backend/
  app.py                        Python server: GET /ping -> pong
  gravitee/pong-api.yaml        API route definition (GKO)
terraform/
  terraform.tfvars              all values to edit (one file)
  variables.tf                  variable definitions
  cluster.tf                    kind cluster, namespaces
  mongodb.tf                    MongoDB
  apim.tf                       Management API + Gateway
  gko.tf                         GKO and ManagementContext
  backend_app.tf                backend pod, ConfigMap, Service
  outputs.tf                    ping_url output
```

## Troubleshooting

Set kubeconfig and check resources:
```bash
export KUBECONFIG=terraform/.kube/pong-gravitee.kubeconfig
kubectl get pods -A
kubectl -n gravitee logs deploy/gravitee-apim-gateway
kubectl -n gravitee logs deploy/gravitee-apim-api
kubectl -n gravitee get apiv4definitions
```

**Connection refused on apply:** The Management API wasn't ready. Run `up` again, or increase `api_apply_delay` in `terraform.tfvars`.

**404 on `/ping`:** Check `kubectl -n gravitee get apiv4definitions` and the GKO logs.

**Empty reply on port 8080:** Check the gateway Service shows `NodePort` with the correct port mapping: `kubectl -n gravitee get svc`.

## Commit to Git

The `.terraform.lock.hcl` file should be committed so everyone gets the same provider versions.

```bash
git add .terraform.lock.hcl
git commit -m "pin provider versions"
```

## Learn More

- [GKO quickstart](https://documentation.gravitee.io/gravitee-kubernetes-operator-gko/getting-started/quickstart-guide)
- [GKO install with Helm](https://documentation.gravitee.io/gravitee-kubernetes-operator-gko/getting-started/installation/install-with-helm)


