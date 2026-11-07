# Troubleshooting guide

| Symptom | Likely cause | Checks / resolution |
|---|---|---|
| `AccessDenied` on `sts:AssumeRole` | Base role lacks `sts:AssumeRole` permission or target trust policy does not trust it | Check `jenkins-assume-deployer-policy.tf`, target role trust and exact role ARN. |
| Jenkins still shows old role | Instance profile not attached, IMDS access blocked, or cached AWS credentials | Check EC2 instance profile in Console; run `aws sts get-caller-identity`; restart build agent process if it caches credentials. |
| Existing CI fails after instance profile change | Old role had permissions not migrated | Restore previous profile, compare CloudTrail denied calls, add narrow required permissions to base role, retry. |
| Terraform says fewer than 3 AZs | Supplied private subnets duplicate AZs or do not span 3 AZs | Inspect `aws ec2 describe-subnets`; choose one private subnet per distinct AZ. |
| Jenkins cannot reach EKS API | Not in same VPC, route/DNS issue, private endpoint disabled? SG ingress missing | Confirm VPC routing, DNS support, cluster endpoint mode and TCP/443 from Jenkins SG. |
| `kubectl` Unauthorized | EKS access entry missing, role ARN mismatch, or auth token using wrong AWS identity | Assume the target role, check `aws sts get-caller-identity`, `aws eks list-access-entries`, and role group mapping. |
| `kubectl` Forbidden | Authentication succeeded but Kubernetes group lacks namespace permissions | Apply `k8s/base/namespaces-and-rbac.yaml`; inspect RoleBinding subjects and group names. |
| Pods Pending with topology constraint | Insufficient nodes/eligible AZs, node selectors/taints, resource pressure | `kubectl describe pod`; inspect node AZ labels, node group subnets and capacity. |
| Pods not balanced across zones | Only one/two AZs eligible or `ScheduleAnyway` used for one constraint | Check all nodes have `topology.kubernetes.io/zone`; confirm node group spans 3 AZs and replicas >=3. |
| HPA shows unknown metrics | metrics-server not installed/healthy or missing resource requests | Install/validate metrics-server; set CPU/memory requests; check `kubectl top pods`. |
| Helm upgrade fails | Wrong namespace RBAC, chart validation, invalid image digest, missing CRD | Check Helm output, `kubectl auth can-i`, digest format, `helm lint`, and target namespace. |
| Image pull failure | Node role lacks ECR pull permission, wrong repo/region, image digest absent | Check node role ECR read permissions, ECR repo, image digest and node-to-ECR connectivity. |
| Ingress not provisioned | AWS Load Balancer Controller missing or annotations/security groups incorrect | Install controller and IAM permissions; enable ingress only after validating its configuration. |
| S3 state lock error | Stale lock or insufficient S3 permissions | Confirm no active Terraform run; follow controlled stale-lock recovery; do not delete locks blindly. |
| AWS Backup selection empty | `enable_jenkins_backup` false or instance ID missing/incorrect | Check `terraform.tfvars`, AWS Backup selection and backup service role permissions. |
| JCasC reload breaks Jenkins | Incomplete config, unsupported plugin configuration, secret source unavailable | Restore backed-up config/EBS; validate on a clone first; do not reload production config without recovery plan. |
