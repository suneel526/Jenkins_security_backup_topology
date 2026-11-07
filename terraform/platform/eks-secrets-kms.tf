resource "aws_kms_key" "eks_secrets" {
  description             = "Customer-managed KMS key for Kubernetes Secret envelope encryption in EKS"
  enable_key_rotation     = true
  deletion_window_in_days = 30
  tags                    = merge(local.common_tags, { Purpose = "EKS Kubernetes Secret encryption" })
}

resource "aws_kms_alias" "eks_secrets" {
  name          = "alias/${var.project_name}-eks-secrets"
  target_key_id = aws_kms_key.eks_secrets.key_id
}

resource "aws_iam_role_policy" "eks_secrets_kms" {
  name = "${var.eks_cluster_name}-secrets-kms"
  role = aws_iam_role.eks_cluster.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "DescribeEKSSecretsKey"
        Effect   = "Allow"
        Action   = ["kms:DescribeKey"]
        Resource = [aws_kms_key.eks_secrets.arn]
      },
      {
        Sid      = "AllowEKSGrantForAWSResource"
        Effect   = "Allow"
        Action   = ["kms:CreateGrant"]
        Resource = [aws_kms_key.eks_secrets.arn]
        Condition = {
          Bool = {
            "kms:GrantIsForAWSResource" = "true"
          }
        }
      }
    ]
  })
}
