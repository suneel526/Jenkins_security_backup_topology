# Start here: step-by-step implementation runbook

## Phase 0 — Discover and protect what already works

1. Log in to the existing Jenkins EC2 instance.
2. Run `../scripts/inspect-jenkins-ec2.sh` from this repository (or copy the script to the host). It reports the EC2 instance ID, region, AZ, VPC ID, subnet ID, security-group IDs, and attached instance profile from IMDSv2. It intentionally does not require you to provide an IP address.
3. In AWS Console → EC2 → Instance → Security, record the attached IAM role/profile. Also inspect attached IAM policies and any instance-profile permissions used by the current CI pipeline.
4. In Jenkins, record the Jenkins version, Java version, installed plugins and versions, job type, SCM URL/branch, script path, credential IDs (IDs only; never secret values), shared libraries, global tools, and build agents.
5. Run `jenkins/export-existing-config.sh` with a Jenkins API token stored in your shell environment. Review the export before committing anything. Remove/replace any secret values if present.
6. Back up the existing EC2/EBS volume using your normal approved process before changing its IAM profile or Jenkins configuration.

**Do not replace the attached EC2 role blindly.** The EC2 metadata service returns credentials for the single IAM role attached to the instance. Attaching `Jenkins-Instance-Profile` replaces the current association. If the old role contains permissions still required by CI, merge those required actions into the new role (least privilege) or use a controlled migration plan. Test the existing CI pipeline after the change.

## Phase 1 — Validate the Hyderabad network

The platform stack reuses an existing VPC to avoid creating a disconnected network beside your live Jenkins EC2.

Required inputs:

- `vpc_id`: existing VPC ID.
- `jenkins_security_group_id`: security group attached to Jenkins EC2, in the same VPC as EKS.
- `private_subnet_ids`: at least three private subnets, each in a distinct AZ, all in that VPC.
- A path from private subnets to required AWS services through NAT gateways or VPC endpoints (ECR API, ECR Docker, S3, STS, EC2, CloudWatch Logs as applicable).
- Jenkins EC2 must reach the private EKS API endpoint on TCP/443.

The Terraform cluster endpoint is private by default. If Jenkins is in another VPC, first design VPC peering/TGW/VPN and DNS/routing/security-group access; otherwise the CD pipeline cannot reach the API. Do not enable public endpoint access to all IPv4 addresses.

## Phase 2 — Bootstrap Terraform remote state

Run the bootstrap stack first; it creates a uniquely named, encrypted, versioned S3 bucket and blocks public access. Bootstrap state remains local, so protect `terraform/bootstrap/terraform.tfstate` and keep it out of Git.

```bash
cd terraform/bootstrap
cp terraform.tfvars.example terraform.tfvars
# Set state_bucket_name to a globally unique name, e.g. company-platform-tfstate-<unique-suffix>.
terraform init
terraform fmt -recursive
terraform validate
terraform plan
terraform apply
terraform output
```

Copy the bucket name and KMS key ARN outputs into `terraform/platform/backend.hcl`. Do not commit that file.

## Phase 3 — Configure and plan the platform stack

```bash
cd ../platform
cp terraform.tfvars.example terraform.tfvars
# Fill vpc_id, jenkins_security_group_id, private_subnet_ids, eks_kubernetes_version,
# and optionally jenkins_instance_id for AWS Backup selection.
cp backend.hcl.example backend.hcl
# Fill bucket, key, region, encrypt, use_lockfile, kms_key_id.
terraform init -backend-config=backend.hcl
terraform fmt -recursive
terraform validate
terraform plan -out=platform.tfplan
terraform show platform.tfplan
```

Review the plan carefully. It creates a new EKS cluster and managed node group in your supplied private subnets, IAM roles, an ECR repository, EKS access entries, and (if enabled and an instance ID is supplied) an AWS Backup plan/selection for the existing Jenkins EC2 instance. It does not attach the instance profile to the existing EC2 instance automatically.

Only after review:

```bash
terraform apply platform.tfplan
terraform output
```

## Phase 4 — Attach the base role safely

1. Confirm whether the existing Jenkins EC2 already has an IAM role.
2. Compare that role's permissions with the new `Jenkins-Base-Role` policy. Preserve the minimum permissions used by the working CI pipeline (for example, pushing to its ECR repository, reading source/artifacts, writing logs, or accessing secrets).
3. Create/attach missing least-privilege policies to the new role before changing the instance profile.
4. In EC2 Console select the existing Jenkins instance → Actions → Security → Modify IAM role → `Jenkins-Instance-Profile`.
5. Re-run `aws sts get-caller-identity`. Expect an assumed-role ARN containing `Jenkins-Base-Role`.
6. Run the existing CI pipeline and verify it still succeeds. Roll back to the previous instance profile if the CI pipeline loses required access; keep the previous policy and role until the new configuration is proven.

## Phase 5 — Configure Kubernetes namespace RBAC

After the EKS cluster is created, configure `kubectl` as an authorized cluster administrator. Apply:

```bash
kubectl apply -f k8s/base/namespaces-and-rbac.yaml
kubectl apply -f k8s/base/storage-class-gp3.yaml
kubectl get namespaces
kubectl get rolebindings -n payment-service-dev
kubectl get rolebindings -n payment-service-qa
kubectl get rolebindings -n payment-service-prod
```

The EKS access entries created by Terraform map each deployment role to a Kubernetes group. The manifest grants only namespace-scoped deployment permissions to the corresponding group. It does not grant cluster-admin.

Test authorization by assuming each role and running `kubectl auth can-i` in its namespace. The role should be able to manage the resources needed by Helm in its own namespace and should not be able to deploy into the other environments.

## Phase 6 — Set up the CD job without changing CI

1. Use `jenkins/export-existing-config.sh` to preserve controller configuration and plugin inventory.
2. Use `jenkins/clone-pipeline-job.sh` only if the existing job is a standard Pipeline/Freestyle job that can be safely copied. It refuses to overwrite a target job, strips inherited trigger definitions, creates the copy disabled, and never updates the source job.
3. In the Jenkins UI, configure the **new** job's SCM script path as `jenkins/Jenkinsfile.cd` (or copy that file to the repository root as `Jenkinsfile.cd`, then set that script path). Keep the original CI job script path and job untouched.
4. Configure `EKS_CLUSTER_NAME` as a Jenkins folder/global environment variable using the output `eks_cluster_name`. Set `AWS_REGION=ap-south-2` if not already inherited from the Jenkinsfile.
5. Ensure the Jenkins execution node has AWS CLI v2, `kubectl`, Helm 3, `jq`, and network access to the private EKS endpoint.
6. The CD job takes `DEPLOY_ENV` and `IMAGE_DIGEST`. Pass a digest like `sha256:<64-lowercase-hex>` from the existing CI pipeline. Do not deploy mutable `latest` tags.
7. Run Dev first; then QA; Production requires a manual approval stage.

## Phase 7 — Application deployment and HA validation

The Helm chart deploys three or more replicas, spreads them across zones and hostnames, sets readiness/liveness/startup probes, CPU/memory requests and limits, a PDB and HPA, and a non-root/read-only container security context.

Verify:

```bash
kubectl get nodes -L topology.kubernetes.io/zone
kubectl get pods -n payment-service-dev -o wide
kubectl get pdb,hpa,svc,deploy -n payment-service-dev
kubectl describe deployment payment-service -n payment-service-dev
```

Check that pods are actually scheduled across distinct zones and hostnames. Topology constraints are scheduling rules; they cannot create capacity or recover unavailable database volumes. Simulate a node drain in a non-production environment and validate the PDB and rescheduling behavior.

## Phase 8 — Security, monitoring and recovery

- Enable ECR image scanning on push and scan with Trivy in CI.
- Use KMS/SSE for state, backup vault, and storage; do not store credentials in Git.
- Review CloudTrail, EKS control-plane logs and CloudWatch alarms.
- Install kube-prometheus-stack with a chart version compatible with your EKS version; specify an explicit version in `monitoring/install-monitoring.sh`.
- Enable AWS Backup for the Jenkins EC2 instance by setting `enable_jenkins_backup=true` and `jenkins_instance_id` in `terraform.tfvars`. For Kubernetes object/PV snapshots, optionally enable Velero with `enable_velero_backup=true` and a unique bucket name, then follow `velero/README.md`.
- Treat EBS/EC2 snapshots as crash-consistent unless application-consistency steps are added. Preserve Jenkins `master.key`/`hudson.util.Secret` through protected snapshots; loss of those keys can make backed-up credentials unreadable.
- Test restoring Jenkins to a separate recovery instance and validate CI before declaring DR ready.
- For EKS persistent volumes, implement CSI snapshots/Velero or AWS Backup selection for the actual EBS volumes and test restore into a separate namespace/cluster.

## Rollback

- Terraform: inspect the plan and use version-controlled configuration. Do not casually run `terraform destroy` in an environment with live Jenkins. Use `terraform plan` before any change.
- Jenkins: restore the pre-change instance profile and the backed-up JENKINS_HOME/EBS snapshot if JCasC or plugin changes damage the controller.
- Helm: the pipeline uses `helm upgrade --install --atomic --wait`, which automatically rolls back a failed upgrade to the previous release where possible. Inspect `helm history` and `helm status` before manual rollback.
- Application: redeploy the last known-good image digest; do not rebuild from an untrusted mutable tag.
