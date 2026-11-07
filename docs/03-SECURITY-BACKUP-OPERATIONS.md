# Security, backups, monitoring and recovery

## IAM and credential handling

- Jenkins base role trust: `ec2.amazonaws.com`; the instance profile is attached to the existing Jenkins EC2 instance only after review.
- Deployment roles trust only the Jenkins base role ARN in the same account.
- The base role can assume only Dev/QA/Prod deployer roles.
- Each deployer role has a permissions boundary and an EKS access entry for a dedicated Kubernetes group.
- Kubernetes RoleBindings grant permissions only inside one application namespace.
- Jenkins uses temporary STS credentials; no IAM user access keys are required.
- Avoid `AdministratorAccess`, broad `iam:PassRole`, or public EKS API access.
- Secrets should live in AWS Secrets Manager or Jenkins credentials. Keep API tokens and secret values out of the repo.

## Container and cluster security

- Enable ECR scan-on-push; use Trivy in CI and fail builds for agreed severity thresholds.
- Promote the same image digest from Dev → QA → Production.
- Run containers as non-root, drop Linux capabilities, set `allowPrivilegeEscalation: false`, and use a read-only root filesystem where supported.
- Set CPU/memory requests and limits; avoid privileged containers and hostPath mounts.
- Apply Kubernetes RBAC and namespaces; use NetworkPolicies only after explicitly allowing required application ingress/egress.
- Keep nodes in private subnets. Use VPC endpoints/NAT with restricted egress.
- Enable CloudTrail and EKS control-plane logs; configure CloudWatch retention/alarms.
- Review security-group rules, EKS public endpoint settings, and node group AMI patching cadence.

## Backup coverage

| Component | Backup approach | Restore test |
|---|---|---|
| Jenkins EC2/EBS | Optional AWS Backup plan in `terraform/platform/backup.tf`; daily and weekly recovery points | Restore to a separate EC2 instance, verify Jenkins and CI, then cut over deliberately |
| Jenkins config | JCasC export + plugin inventory + job configuration in private Git | Recreate controller in a test instance |
| Jenkins credentials | Protected EBS/EC2 backup retaining `master.key` and `hudson.util.Secret`; keep key backup access restricted | Verify credential decryption only in a controlled recovery instance |
| Terraform state | Encrypted, versioned S3 state bucket; native S3 lock file | Restore an older object version only with an approved recovery procedure |
| Container images | ECR retention policy; immutable image tags | Redeploy by digest |
| Kubernetes manifests/Helm | Git repository is source of truth | Recreate namespaces, RBAC, releases |
| EKS persistent volumes | Configure EBS CSI snapshots/Velero/AWS Backup for actual data volumes | Restore to isolated namespace/cluster and validate data |
| Database | Use database-native backups/PITR and multi-AZ architecture when applicable | Restore to a separate database and run application checks |

AWS Backup protection for the Jenkins EC2 instance is optional. Set both `enable_jenkins_backup = true` and `jenkins_instance_id` only after checking cost, retention and required service permissions. Optionally set `jenkins_home_backup_bucket_name` to create a private, versioned, KMS-encrypted bucket for the home archive helper. Terraform grants the Jenkins base role write-only access to the `jenkins-home/` prefix when this option is enabled; archive expiration is controlled by `jenkins_home_backup_retention_days`. The AWS Backup role is created by Terraform. EBS snapshots are normally crash-consistent unless the workload is quiesced or application-consistent backup is configured.

The included Jenkins-home archive helper is optional and writes a sensitive archive to an S3 bucket with SSE-KMS. It may capture credentials and encryption keys. Restrict the bucket and KMS key to the recovery administrators only. For consistent recovery, prefer EBS/EC2 backup and a tested restore process; do not rely on a live tar archive alone.

## Suggested starting RPO/RTO discussion

Do not assume universal values. Ask the application owner/business to define:

- RPO: maximum acceptable data loss measured in time.
- RTO: maximum acceptable service restoration time.
- Backup frequency and retention to satisfy those objectives.
- Whether the service can tolerate an AZ outage, node outage, region outage, or Jenkins controller outage.
- Who can approve restore and Production cutover.

Run restore drills at a defined cadence and record measured RPO/RTO.

## Monitoring

The EKS add-ons include EBS CSI with an IRSA role and the repository includes an encrypted gp3 StorageClass. Confirm the driver is healthy before creating PVCs. Install metrics-server for HPA metrics.

The `monitoring/` folder includes values for kube-prometheus-stack and an installer that requires an explicit chart version. Configure persistent volumes, storage class, retention, alert receivers and Grafana authentication before production use. Also enable CloudWatch EKS control-plane logs and Container Insights if required by your organization.

## Operational checks

```bash
# AWS identity / role
aws sts get-caller-identity

# Cluster reachability
aws eks describe-cluster --name "$EKS_CLUSTER_NAME" --region ap-south-2
kubectl get nodes -L topology.kubernetes.io/zone

# App state and distribution
kubectl get pods -n payment-service-dev -o wide
kubectl get deploy,svc,hpa,pdb -n payment-service-dev

# Helm history / rollback
helm history payment-service -n payment-service-dev
helm status payment-service -n payment-service-dev
```
