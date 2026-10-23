# Developer notes

How the code works and why. Written for a reviewer reading the repository.

## Flow of `python run.py up`

1. `check_tools` confirms `docker` and `terraform` are on the PATH and that Docker answers.
2. `terraform init`, then `terraform apply -auto-approve`. If the apply fails it waits 15 seconds and runs once more. Some resources depend on pods that are still starting (see "Why GKO needs a wait"), and a second apply continues from where the first stopped.
3. `ping_url()` reads the `ping_url` Terraform output. The port is therefore set only in `terraform.tfvars`.
4. `wait_for_pong` calls the URL every 5 seconds, for up to 180 seconds (`PONG_WAIT_SECONDS` overrides it), until the body is exactly `pong`.

`test` calls the same URL once. `down` runs `terraform destroy`. The script uses only the standard library.

## Terraform dependency order

```
kind_cluster
  -> namespaces (gravitee, backend)
       -> MongoDB: random passwords -> Secrets -> StatefulSet
            -> helm_release.apim (Management API + Gateway)
                 -> helm_release.gko
                      -> ManagementContext
                           -> time_sleep (wait for the Management API)
                                -> ApiV4Definition pong-api  (also after the backend Deployment)
       -> backend: ConfigMap -> Deployment -> Service
```

Providers are configured from the kind cluster's own outputs (`providers.tf`), so no kubeconfig on the host is needed.

## Decisions worth knowing

**`kubectl` provider for GKO resources.** `kubernetes_manifest` validates against the CRD schema at plan time. On a new cluster the GKO CRDs do not exist yet, so the plan fails. `kubectl_manifest` sends the YAML at apply time.

**No `upgrade_install` on the Helm releases.** With it, the provider looks up the release while planning. On a new cluster the provider has no connection yet and fails with "Kubernetes cluster unreachable". Without it, Terraform still runs `helm upgrade` when values change.

**Why GKO needs a wait.** When an `ApiV4Definition` is applied, GKO's admission webhook calls the Management API. If the Management API is not answering, the apply is rejected. `time_sleep.wait_for_management_api` waits `api_apply_delay` before the API is applied. Its triggers are hashes of the apim and gko inputs, so it waits on first install and whenever those change, and does not show a change in every plan.

**`wait = true` on `pong_api`.** GKO puts a finalizer on the API. Deleting the API returns before the finalizer finishes, and deleting the `ManagementContext` is then rejected because one API still uses it. `wait = true` makes the provider wait for the finalizer, so `down` works on the first run.

**MongoDB credentials.** Terraform generates the root and application passwords (`random_password`) and stores them in Secrets. The application user is created by a script on the first start (`/docker-entrypoint-initdb.d`). The chart would write the password into a ConfigMap, so the connection string comes from a Secret through `gravitee_management_mongodb_uri` and `gravitee_ratelimit_mongodb_uri`, which override the chart's setting. Because the setup script runs only on an empty data directory, changing the password later needs the volume to be recreated.

**MongoDB probes.** They use TCP on the pod IP. During first-start setup MongoDB listens only on localhost, so the pod becomes ready only after setup is complete.

**Official `mongo` image.** The Bitnami image on Docker Hub publishes only a floating `latest` tag. A tag that cannot be pinned makes runs differ over time, and Gravitee's own chart now points at `bitnamilegacy` for the same reason.

**Backend.** `backend/app.py` serves `/ping` (`pong`) and `/healthz` (`ok`, used by the probes and left out of the logs). As PID 1 in a container, Python ignores SIGTERM unless a handler is set, so a pod would take the full grace period to stop. The handler calls `server.shutdown()` in a thread and the pod stops in under a second. The source is mounted from a ConfigMap, and its SHA-256 is an annotation on the pod, so editing `app.py` restarts the pod.

**Pod security.** The backend namespace enforces `restricted`. The pod meets it: non-root, seccomp `RuntimeDefault`, no privilege escalation, all capabilities dropped, read-only root filesystem. The `gravitee` namespace only audits `restricted`, because it runs third-party charts.

**Access from the host.** kind maps host port `gateway_host_port` (8080) to the gateway Service's NodePort (30082, from `apim_values`). There is no ingress controller. Both numbers come from `terraform.tfvars`: the node port is read from `apim_values.gateway.service.nodePort`.



