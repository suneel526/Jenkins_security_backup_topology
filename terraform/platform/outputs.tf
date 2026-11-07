output "aws_account_id" {
  value       = data.aws_caller_identity.current.account_id
  description = "AWS account ID detected dynamically"
}

output "jenkins_base_role_arn" {
  value = aws_iam_role.jenkins_base.arn
}

output "jenkins_instance_profile_name" {
  value = aws_iam_instance_profile.jenkins.name
}

output "dev_deployer_role_arn" {
  value = aws_iam_role.deployer["dev"].arn
}

output "qa_deployer_role_arn" {
  value = aws_iam_role.deployer["qa"].arn
}

output "prod_deployer_role_arn" {
  value = aws_iam_role.deployer["prod"].arn
}

output "eks_cluster_name" {
  value = aws_eks_cluster.this.name
}

output "eks_cluster_endpoint" {
  value       = aws_eks_cluster.this.endpoint
  description = "Private endpoint; Jenkins must have network reachability to it"
}

output "ecr_repository_url" {
  value = aws_ecr_repository.payment_service.repository_url
}

output "jenkins_backup_vault_name" {
  value = aws_backup_vault.jenkins.name
}

output "jenkins_backup_kms_key_arn" {
  value       = aws_kms_key.jenkins_backup.arn
  description = "KMS key for Jenkins Backup vault and optional home archive bucket"
}

output "jenkins_home_backup_bucket_name" {
  value       = try(aws_s3_bucket.jenkins_home_backup[0].bucket, null)
  description = "Optional S3 bucket for encrypted JENKINS_HOME archives"
}

output "velero_backup_bucket_name" {
  value       = try(aws_s3_bucket.velero[0].bucket, null)
  description = "Optional S3 bucket for Velero Kubernetes object backups"
}

output "velero_iam_role_arn" {
  value       = try(aws_iam_role.velero[0].arn, null)
  description = "Optional IRSA role ARN to annotate the Velero ServiceAccount"
}

output "eks_secrets_kms_key_arn" {
  value       = aws_kms_key.eks_secrets.arn
  description = "Customer-managed KMS key used for EKS Kubernetes Secret encryption"
}
