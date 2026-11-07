# Jenkins + AWS + EKS deployment platform (single AWS account, Hyderabad)

This repository is a **production-oriented starter project**, tailored to the following known facts:

- One AWS account only.
- AWS region: `ap-south-2` (Asia Pacific – Hyderabad).
- Jenkins is already installed on an existing EC2 instance in `ap-south-2`.
- The existing CI pipeline is working and must remain unchanged.
- A separate CD pipeline will deploy `payment-service` to `dev`, `qa`, and `prod`.
- Terraform manages AWS IAM/EKS/ECR/backup resources; Helm deploys the application.
- Jenkins obtains its initial AWS credentials from an EC2 instance profile, then assumes a same-account environment role with STS.

> **Important:** This project does not know your AWS account ID, Jenkins instance ID, VPC ID, security group ID, private subnet IDs, EKS Kubernetes version, or existing Jenkins job type. Those are intentionally inputs, not fabricated values. Complete `terraform/platform/terraform.tfvars` from the example and the preflight instructions before running `terraform apply`.

## What is included

- `terraform/bootstrap/`: creates a versioned, encrypted S3 bucket for the main Terraform state. Run this first with local state.
- `terraform/platform/`: creates the Jenkins base IAM role and instance profile, environment deployment roles, permissions boundary, ECR repository, an EKS cluster in your **existing VPC/private subnets**, EKS access entries, and optional AWS Backup protection for the existing Jenkins EC2 instance, and optional Velero S3/EBS snapshot backup for EKS namespaces.
- `jenkins/`: JCasC export and plugin inventory, a sanitized clone script that strips inherited triggers and creates the copy disabled, a minimal JCasC starter file, an optional Trivy CI snippet, and a separate `Jenkinsfile.cd`.
- `k8s/`: namespace-scoped RBAC for Dev/QA/Prod, plus topology-spread examples.
- `helm/payment-service/`: an application chart with topology spread, probes, security context, HPA, PDB, optional Ingress and optional NetworkPolicy.
- `monitoring/`: kube-prometheus-stack values, a pinned installation helper, and a metrics-server installer required by HPA.
- `velero/`: optional Velero Helm values and daily Kubernetes/EBS backup schedule.
- `k8s/base/storage-class-gp3.yaml`: encrypted gp3 EBS CSI StorageClass; Terraform configures EBS CSI with IRSA.
- `scripts/`: inspect the existing Jenkins EC2 instance, verify STS role assumption, validate prerequisites, and make a protected Jenkins-home archive.
- `docs/`: implementation order, architecture, cloning guidance, backup/restore and operational notes.

## Deployment sequence (do not skip)

1. Read `docs/00-START-HERE.md` and `docs/01-ARCHITECTURE.md`.
2. On the existing Jenkins EC2 instance, run `scripts/inspect-jenkins-ec2.sh`. Record the VPC, subnet, AZ, and security-group IDs. No public/private IP needs to be pasted into Terraform for IAM.
3. Back up Jenkins and export its current JCasC/plugin inventory using `jenkins/export-existing-config.sh`. Do not apply JCasC yet.
4. Confirm that the existing Jenkins VPC is the VPC you intend to use for EKS. The EKS API endpoint is private by default. Jenkins must have network reachability to the endpoint; the existing Jenkins security group is allowed to the EKS control-plane security group on TCP/443.
5. Ensure the VPC has at least three **private subnets in three distinct Availability Zones**, suitable routing/NAT or required VPC endpoints, and enough node capacity. This project deliberately reuses your existing VPC; it does not silently create a second VPC that your existing Jenkins EC2 cannot reach.
6. Run `terraform/bootstrap` to create the remote-state bucket. Configure `terraform/platform/backend.hcl` and initialize the platform stack.
7. Fill `terraform/platform/terraform.tfvars` and run `terraform plan`. Review changes before apply.
8. Attach the created `Jenkins-Instance-Profile` to the existing Jenkins EC2 instance **only after reviewing its current instance profile and permissions**. An EC2 instance can have only one attached IAM role at a time. Merge required existing permissions into the new base role or plan a controlled migration; do not blindly replace a role that the running CI pipeline relies on.
9. Verify `aws sts get-caller-identity`, then test role assumption using `scripts/verify-assume-role.sh`.
10. Apply `k8s/base/namespaces-and-rbac.yaml` using an authorized cluster administrator. Apply the optional network policy only after adapting its allowed traffic.
11. Clone the existing Jenkins job into a new job name using `jenkins/clone-pipeline-job.sh` only for a compatible standard job. The source CI job is never updated by this script. Configure the new job to use `jenkins/Jenkinsfile.cd` or point its SCM script path to `Jenkinsfile.cd`.
12. Review JCasC exports and the example. Keep secrets out of Git. Apply JCasC only after testing on a non-production controller or a restorable clone.
13. Configure the CD job's `EKS_CLUSTER_NAME` global/folder environment variable and run a Dev deployment using an immutable `sha256:` image digest produced by CI.
14. Validate QA, then enable the Production approval path and deploy to Production.
15. Configure monitoring, backup schedules, restore tests, and alerting.

## Terraform commands

### Bootstrap state bucket

```bash
cd terraform/bootstrap
cp terraform.tfvars.example terraform.tfvars
# Edit state_bucket_name to a globally unique name.
terraform init
terraform fmt -recursive
terraform validate
terraform plan
terraform apply
terraform output
```

### Platform stack

```bash
cd ../platform
cp terraform.tfvars.example terraform.tfvars
# Edit all required values. Do not use the example placeholders literally.
cp backend.hcl.example backend.hcl
# Edit backend.hcl using the bootstrap outputs.
terraform init -backend-config=backend.hcl
terraform fmt -recursive
terraform validate
terraform plan
terraform apply
```

The platform state uses S3 native lock files (`use_lockfile = true`), supported by Terraform 1.10 and later. EKS VPC CNI and EBS CSI add-ons use dedicated IRSA roles; an encrypted gp3 StorageClass is included for persistent monitoring data. The state bucket must have versioning enabled. The bootstrap stack itself intentionally uses local state; keep its state file safe and encrypted.

## Current limitations you must account for

- The EKS cluster is created in an existing VPC. You must supply three private subnet IDs in three distinct AZs and the Jenkins EC2 security-group ID. If Jenkins is not in the same VPC, establish private connectivity before using a private EKS endpoint; do not solve this by opening the cluster API to `0.0.0.0/0`.
- The EKS cluster version is a required input. Select a Kubernetes version currently supported by EKS in `ap-south-2` and compatible with your add-ons before planning.
- EKS access entries map deployment IAM roles to Kubernetes groups. Namespace Roles and RoleBindings must be applied by an administrator once. The deployment roles do not get cluster-admin privileges.
- The chart assumes your application listens on port `8080` and exposes `/health/ready` and `/health/live`. Change these to match your application.
- The chart runs as UID/GID `10001` with a read-only root filesystem. Ensure your image supports non-root execution and writes only to mounted writable paths.
- The ALB Ingress template is disabled by default. Install and configure AWS Load Balancer Controller before enabling it.
- The NetworkPolicy template is disabled by default because application egress requirements (database, APIs, DNS, telemetry) are workload-specific.
- EBS-backed persistent volumes require a compatible CSI driver and storage/snapshot design. The README does not claim that Pod topology spread alone makes stateful data highly available.
- The Terraform IAM permissions are intentionally narrow for EKS/Helm deployment. If your build/deploy process performs extra AWS operations, add narrowly scoped permissions rather than `AdministratorAccess`.

## Do not do these things

- Do not overwrite the existing CI job or its `Jenkinsfile`.
- Do not paste AWS access keys into Jenkinsfiles, YAML, Terraform variables, or Git.
- Do not use the EKS OIDC/IRSA ServiceAccount setup for the existing EC2-hosted Jenkins controller. This project uses the EC2 instance profile for Jenkins.
- Do not assume JCasC exports jobs, plugin binaries, build history, or all secret material. Back up `JENKINS_HOME`/EBS and preserve the Jenkins encryption keys.
- Do not apply Production changes before validating Dev and QA.

See `docs/00-START-HERE.md` for the full runbook.


Optional JENKINS_HOME archive retention is controlled by `jenkins_home_backup_retention_days` (default 90 days). The Jenkins base role receives narrowly scoped upload permissions only when the archive bucket is enabled.
# Jenkins_security_backup_topology
