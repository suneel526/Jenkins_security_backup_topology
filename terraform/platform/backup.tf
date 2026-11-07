# Optional AWS Backup protection for the already-existing Jenkins EC2 instance.
# Set enable_jenkins_backup=true and jenkins_instance_id in terraform.tfvars.

data "aws_instance" "jenkins" {
  count       = var.enable_jenkins_backup && var.jenkins_instance_id != "" ? 1 : 0
  instance_id = var.jenkins_instance_id
}

resource "aws_kms_key" "jenkins_backup" {
  description             = "KMS key for Jenkins AWS Backup vault and optional JENKINS_HOME archive bucket"
  enable_key_rotation     = true
  deletion_window_in_days = 30
  tags                    = local.common_tags
}

resource "aws_kms_alias" "jenkins_backup" {
  name          = "alias/${var.project_name}-jenkins-backup"
  target_key_id = aws_kms_key.jenkins_backup.key_id
}

resource "aws_backup_vault" "jenkins" {
  name        = "${var.project_name}-jenkins-vault"
  kms_key_arn = aws_kms_key.jenkins_backup.arn
  tags        = local.common_tags
}

resource "aws_iam_role" "backup" {
  name = "${var.project_name}-aws-backup-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = { Service = "backup.amazonaws.com" }
      Action = "sts:AssumeRole"
    }]
  })
  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "backup_service" {
  role       = aws_iam_role.backup.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForBackup"
}

resource "aws_iam_role_policy_attachment" "backup_restore_service" {
  role       = aws_iam_role.backup.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForRestores"
}

resource "aws_iam_role_policy" "backup_kms" {
  name = "${var.project_name}-backup-kms-use"
  role = aws_iam_role.backup.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = ["kms:Decrypt", "kms:DescribeKey", "kms:GenerateDataKey", "kms:GenerateDataKeyWithoutPlaintext", "kms:CreateGrant"]
      Resource = [aws_kms_key.jenkins_backup.arn]
    }]
  })
}

resource "aws_s3_bucket" "jenkins_home_backup" {
  count         = var.jenkins_home_backup_bucket_name != "" ? 1 : 0
  bucket        = var.jenkins_home_backup_bucket_name
  force_destroy = false
  tags          = merge(local.common_tags, { Purpose = "Protected Jenkins home archive" })
}

resource "aws_s3_bucket_versioning" "jenkins_home_backup" {
  count  = var.jenkins_home_backup_bucket_name != "" ? 1 : 0
  bucket = aws_s3_bucket.jenkins_home_backup[0].id
  versioning_configuration { status = "Enabled" }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "jenkins_home_backup" {
  count  = var.jenkins_home_backup_bucket_name != "" ? 1 : 0
  bucket = aws_s3_bucket.jenkins_home_backup[0].id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.jenkins_backup.arn
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "jenkins_home_backup" {
  count                   = var.jenkins_home_backup_bucket_name != "" ? 1 : 0
  bucket                  = aws_s3_bucket.jenkins_home_backup[0].id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_backup_plan" "jenkins" {
  name = "${var.project_name}-jenkins-ec2-backup"

  rule {
    rule_name                = "JenkinsDaily"
    target_backup_vault_name = aws_backup_vault.jenkins.name
    schedule                 = "cron(30 18 * * ? *)" # 18:30 UTC = 00:00 IST next day
    start_window             = 60
    completion_window        = 360

    lifecycle {
      delete_after = var.backup_daily_retention_days
    }
  }

  rule {
    rule_name                = "JenkinsWeekly"
    target_backup_vault_name = aws_backup_vault.jenkins.name
    schedule                 = "cron(0 19 ? * SAT *)" # 19:00 UTC Saturday = 00:30 IST Sunday
    start_window             = 60
    completion_window        = 360

    lifecycle {
      delete_after = var.backup_weekly_retention_days
    }
  }

  tags = local.common_tags
}

resource "aws_backup_selection" "jenkins" {
  count        = var.enable_jenkins_backup && var.jenkins_instance_id != "" ? 1 : 0
  name         = "${var.project_name}-existing-jenkins-instance"
  iam_role_arn = aws_iam_role.backup.arn
  plan_id      = aws_backup_plan.jenkins.id

  resources = [data.aws_instance.jenkins[0].arn]
}



resource "aws_s3_bucket_lifecycle_configuration" "jenkins_home_backup" {
  count  = var.jenkins_home_backup_bucket_name != "" ? 1 : 0
  bucket = aws_s3_bucket.jenkins_home_backup[0].id

  rule {
    id     = "expire-jenkins-home-archives"
    status = "Enabled"
    filter { prefix = "jenkins-home/" }
    expiration { days = var.jenkins_home_backup_retention_days }
    abort_incomplete_multipart_upload { days_after_initiation = 7 }
  }
}

resource "aws_s3_bucket_policy" "jenkins_home_backup_tls_only" {
  count  = var.jenkins_home_backup_bucket_name != "" ? 1 : 0
  bucket = aws_s3_bucket.jenkins_home_backup[0].id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "DenyInsecureTransport"
      Effect    = "Deny"
      Principal = "*"
      Action    = "s3:*"
      Resource = [
        aws_s3_bucket.jenkins_home_backup[0].arn,
        "${aws_s3_bucket.jenkins_home_backup[0].arn}/*"
      ]
      Condition = { Bool = { "aws:SecureTransport" = "false" } }
    }]
  })
}


# Optional Velero resources for Kubernetes object backups and EBS volume snapshots.
# The Helm chart and Schedule manifest are under ../../velero/.
resource "aws_s3_bucket" "velero" {
  count         = var.enable_velero_backup ? 1 : 0
  bucket        = var.velero_backup_bucket_name
  force_destroy = false
  tags          = merge(local.common_tags, { Purpose = "Velero Kubernetes backups" })
}

resource "aws_s3_bucket_versioning" "velero" {
  count  = var.enable_velero_backup ? 1 : 0
  bucket = aws_s3_bucket.velero[0].id
  versioning_configuration { status = "Enabled" }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "velero" {
  count  = var.enable_velero_backup ? 1 : 0
  bucket = aws_s3_bucket.velero[0].id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.jenkins_backup.arn
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "velero" {
  count                   = var.enable_velero_backup ? 1 : 0
  bucket                  = aws_s3_bucket.velero[0].id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "velero" {
  count  = var.enable_velero_backup ? 1 : 0
  bucket = aws_s3_bucket.velero[0].id

  rule {
    id     = "expire-noncurrent-velero-backups"
    status = "Enabled"
    filter {}
    noncurrent_version_expiration { noncurrent_days = 45 }
    abort_incomplete_multipart_upload { days_after_initiation = 7 }
  }
}

resource "aws_s3_bucket_policy" "velero_tls_only" {
  count  = var.enable_velero_backup ? 1 : 0
  bucket = aws_s3_bucket.velero[0].id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "DenyInsecureTransport"
      Effect    = "Deny"
      Principal = "*"
      Action    = "s3:*"
      Resource = [aws_s3_bucket.velero[0].arn, "${aws_s3_bucket.velero[0].arn}/*"]
      Condition = { Bool = { "aws:SecureTransport" = "false" } }
    }]
  })
}

resource "aws_iam_role" "velero" {
  count = var.enable_velero_backup ? 1 : 0
  name  = "${var.eks_cluster_name}-velero-backup-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = { Federated = aws_iam_openid_connect_provider.eks.arn }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${local.eks_oidc_issuer_hostpath}:aud" = "sts.amazonaws.com"
          "${local.eks_oidc_issuer_hostpath}:sub" = "system:serviceaccount:velero:velero-server"
        }
      }
    }]
  })
  tags = local.common_tags
}

resource "aws_iam_role_policy" "velero" {
  count = var.enable_velero_backup ? 1 : 0
  name  = "${var.eks_cluster_name}-velero-backup-access"
  role  = aws_iam_role.velero[0].id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "VeleroS3BucketAccess"
        Effect = "Allow"
        Action = ["s3:GetBucketLocation", "s3:ListBucket"]
        Resource = [aws_s3_bucket.velero[0].arn]
      },
      {
        Sid    = "VeleroS3ObjectAccess"
        Effect = "Allow"
        Action = ["s3:AbortMultipartUpload", "s3:DeleteObject", "s3:GetObject", "s3:PutObject"]
        Resource = ["${aws_s3_bucket.velero[0].arn}/*"]
      },
      {
        Sid    = "VeleroEbsSnapshotOperations"
        Effect = "Allow"
        Action = [
          "ec2:CreateSnapshot", "ec2:CreateTags", "ec2:CreateVolume",
          "ec2:DeleteSnapshot", "ec2:DeleteVolume", "ec2:DescribeInstances",
          "ec2:DescribeSnapshots", "ec2:DescribeTags", "ec2:DescribeVolumes"
        ]
        Resource = "*"
      },
      {
        Sid    = "VeleroBackupKmsUsage"
        Effect = "Allow"
        Action = ["kms:CreateGrant", "kms:Decrypt", "kms:DescribeKey", "kms:GenerateDataKey", "kms:ReEncrypt*"]
        Resource = [aws_kms_key.jenkins_backup.arn]
      }
    ]
  })
}
