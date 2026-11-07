# Terraform platform stack

This stack is for one AWS account in `ap-south-2` (Hyderabad). It reuses an existing VPC and the private subnets supplied in `terraform.tfvars`; it does not create or move the existing Jenkins EC2 instance.

## Required inputs

- `vpc_id`: VPC containing Jenkins and the target EKS private subnets.
- `jenkins_security_group_id`: the current Jenkins EC2 security group, in that VPC.
- `private_subnet_ids`: at least three private subnets in three distinct AZs and the supplied VPC.
- `eks_kubernetes_version`: a Kubernetes version currently supported by EKS in `ap-south-2`.
- `jenkins_instance_id` only when enabling AWS Backup selection for the existing Jenkins EC2 instance.

Use `terraform.tfvars.example` as a starting point. Never commit the completed `terraform.tfvars`, `backend.hcl`, state files, plan files, or credential material.

## Existing Jenkins IAM migration

The configuration creates a role named `Jenkins-Base-Role` and an instance profile named `Jenkins-Instance-Profile`. Before applying, check whether either already exists. If the role already exists and is the intended role, import it into this state only after reviewing its policies and current Terraform ownership; do not create a duplicate role or let Terraform take over an object managed elsewhere. An EC2 instance has one attached IAM role at a time. Preserve permissions required by the working CI pipeline before switching its instance profile.

## Optional backups

- `enable_jenkins_backup=true` plus `jenkins_instance_id` enables AWS Backup selection for the existing EC2 instance.
- `jenkins_home_backup_bucket_name` creates a private, versioned, KMS-encrypted archive bucket and grants the base role write-only access to `jenkins-home/`.
- `enable_velero_backup=true` plus `velero_backup_bucket_name` creates the Velero bucket and IRSA role. Replace the outputs in `velero/values.yaml` and review the plugin/chart version compatibility before installation.

The backup schedules are examples. Validate time zone, retention, cost, KMS access, and actual restore procedures against business RPO/RTO requirements.

## Apply safely

```bash
terraform init -backend-config=backend.hcl
terraform fmt -recursive
terraform validate
terraform plan -out=platform.tfplan
terraform show platform.tfplan
# Apply only after reviewing the entire plan:
terraform apply platform.tfplan
```

The EKS endpoint is private by default. Jenkins must have network reachability to the EKS API endpoint and AWS service endpoints (or NAT egress) needed by the pipeline and nodes. EKS Kubernetes Secrets use a customer-managed KMS key; do not remove or schedule deletion of that key while the cluster depends on it.


## If the Jenkins IAM role/profile already exists

After initializing the platform backend, and only after confirming the existing objects are the intended resources and are not already managed by another Terraform state, import them instead of attempting to create duplicates:

```bash
terraform import aws_iam_role.jenkins_base Jenkins-Base-Role
terraform import aws_iam_instance_profile.jenkins Jenkins-Instance-Profile
terraform plan
```

Review the plan carefully. Importing does not automatically preserve every policy from the old role in this configuration; inventory attached and inline policies first, then add required permissions to Terraform before changing the EC2 instance profile.
