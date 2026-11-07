resource "aws_iam_role" "jenkins_base" {
  name                 = "Jenkins-Base-Role"
  description          = "Base EC2 role for the existing Jenkins instance in ap-south-2"
  max_session_duration = 3600

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "AllowEC2InstanceProfile"
      Effect = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action = "sts:AssumeRole"
    }]
  })

  tags = local.common_tags
}

resource "aws_iam_instance_profile" "jenkins" {
  name = "Jenkins-Instance-Profile"
  role = aws_iam_role.jenkins_base.name
  tags = local.common_tags
}

resource "aws_iam_policy" "deployment_boundary" {
  name        = "Payment-Service-Deployment-Permissions-Boundary"
  description = "Maximum AWS API permissions for environment deployment roles; Kubernetes RBAC further scopes each namespace"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "AllowReadOnlyEKSClusterDiscovery"
      Effect = "Allow"
      Action = ["eks:DescribeCluster", "ecr:DescribeImages"]
      Resource = [local.cluster_arn, aws_ecr_repository.payment_service.arn]
    }]
  })

  tags = local.common_tags
}

resource "aws_iam_role" "deployer" {
  for_each = local.environment_roles

  name                 = each.value.name
  description          = "Same-account ${each.key} deployment role for payment-service"
  max_session_duration = 3600
  permissions_boundary = aws_iam_policy.deployment_boundary.arn

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "TrustJenkinsBaseRoleOnly"
      Effect = "Allow"
      Principal = { AWS = aws_iam_role.jenkins_base.arn }
      Action = "sts:AssumeRole"
    }]
  })

  tags = merge(local.common_tags, { Environment = each.key })
}

resource "aws_iam_role_policy" "jenkins_assume_deployers" {
  name = "Jenkins-Assume-Environment-Deployer-Roles"
  role = aws_iam_role.jenkins_base.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "AssumeOnlyPaymentServiceEnvironmentRoles"
      Effect = "Allow"
      Action = ["sts:AssumeRole"]
      Resource = [for role in aws_iam_role.deployer : role.arn]
    }]
  })
}

resource "aws_iam_role_policy" "deployer_eks_describe" {
  for_each = local.environment_roles
  name     = "${var.project_name}-${each.key}-eks-describe"
  role     = aws_iam_role.deployer[each.key].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid      = "DescribeOnlyTargetEKSCluster"
      Effect   = "Allow"
      Action   = ["eks:DescribeCluster", "ecr:DescribeImages"]
      Resource = [local.cluster_arn, aws_ecr_repository.payment_service.arn]
    }]
  })
}

resource "aws_iam_policy" "jenkins_ecr_push" {
  name        = "Jenkins-Payment-Service-ECR-Push"
  description = "Allows the existing Jenkins CI pipeline to push images to the payment-service ECR repository"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "GetECRAuthorizationToken"
        Effect   = "Allow"
        Action   = ["ecr:GetAuthorizationToken"]
        Resource = "*"
      },
      {
        Sid    = "PushOnlyPaymentServiceRepository"
        Effect = "Allow"
        Action = [
          "ecr:BatchCheckLayerAvailability",
          "ecr:CompleteLayerUpload",
          "ecr:DescribeImages",
          "ecr:DescribeRepositories",
          "ecr:InitiateLayerUpload",
          "ecr:PutImage",
          "ecr:UploadLayerPart"
        ]
        Resource = [aws_ecr_repository.payment_service.arn]
      }
    ]
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "jenkins_ecr_push" {
  role       = aws_iam_role.jenkins_base.name
  policy_arn = aws_iam_policy.jenkins_ecr_push.arn
}

resource "aws_iam_policy" "iam_guardrail" {
  name        = "Jenkins-Prevent-Long-Lived-IAM-Credentials"
  description = "Explicitly denies creation of IAM users and access keys by Jenkins deployment identities"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "PreventLongLivedIAMCredentials"
      Effect = "Deny"
      Action = ["iam:CreateAccessKey", "iam:CreateUser"]
      Resource = "*"
    }]
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "iam_guardrail" {
  for_each = merge(
    { jenkins = aws_iam_role.jenkins_base.name },
    { for env, role in aws_iam_role.deployer : env => role.name }
  )

  role       = each.value
  policy_arn = aws_iam_policy.iam_guardrail.arn
}


# Optional: allow the Jenkins EC2 role to stream JENKINS_HOME archives to its
# dedicated private S3 bucket. No read/list access to archive objects is granted.
resource "aws_iam_role_policy" "jenkins_home_backup_upload" {
  count = var.jenkins_home_backup_bucket_name != "" ? 1 : 0
  name  = "Jenkins-Home-Backup-Upload"
  role  = aws_iam_role.jenkins_base.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "WriteOnlyToJenkinsBackupPrefix"
        Effect   = "Allow"
        Action   = ["s3:PutObject", "s3:AbortMultipartUpload", "s3:ListMultipartUploadParts"]
        Resource = ["${aws_s3_bucket.jenkins_home_backup[0].arn}/jenkins-home/*"]
      },
      {
        Sid      = "GetBackupBucketLocation"
        Effect   = "Allow"
        Action   = ["s3:GetBucketLocation"]
        Resource = [aws_s3_bucket.jenkins_home_backup[0].arn]
      },
      {
        Sid      = "UseBackupKMSKeyForUpload"
        Effect   = "Allow"
        Action   = ["kms:Encrypt", "kms:GenerateDataKey", "kms:DescribeKey"]
        Resource = [aws_kms_key.jenkins_backup.arn]
      }
    ]
  })
}
