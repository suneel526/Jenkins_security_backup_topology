# payment-service Helm chart

- Assumes container port 8080 and HTTP health paths `/health/ready` and `/health/live`; change values if the app differs.
- Requires immutable ECR image repository and `sha256:` digest supplied by the CD pipeline.
- Uses three replicas, zone + hostname topology spread, readiness/liveness/startup probes, PDB, HPA and non-root/read-only container security context.
- Set `ingress.enabled=true` only after AWS Load Balancer Controller is installed and annotations/hostnames are reviewed.
- Set `networkPolicy.enabled=true` only after adding all application-specific egress rules (database, APIs, telemetry, DNS). The default is disabled to avoid breaking dependencies.
- `serviceAccount.create=false`; this chart uses the namespace's `default` ServiceAccount and does not create IAM permissions for the application. Add a dedicated workload identity design (EKS Pod Identity/IRSA) if the application itself needs AWS access.
