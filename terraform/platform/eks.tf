resource "aws_security_group" "eks_control_plane_access" {
  name        = "${var.eks_cluster_name}-api-from-jenkins"
  description = "Allow the existing Jenkins EC2 security group to reach the private EKS API"
  vpc_id      = var.vpc_id

  ingress {
    description     = "Kubernetes API from Jenkins EC2 security group"
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    security_groups = [var.jenkins_security_group_id]
  }

  egress {
    description = "Allow control-plane response and required outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, { Name = "${var.eks_cluster_name}-api-from-jenkins" })
}

resource "aws_iam_role" "eks_cluster" {
  name = "${var.eks_cluster_name}-cluster-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = { Service = "eks.amazonaws.com" }
      Action = "sts:AssumeRole"
    }]
  })
  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "eks_cluster_policy" {
  role       = aws_iam_role.eks_cluster.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonEKSClusterPolicy"
}

resource "aws_cloudwatch_log_group" "eks_control_plane" {
  name              = "/aws/eks/${var.eks_cluster_name}/cluster"
  retention_in_days = 90
  tags              = local.common_tags
}

resource "aws_eks_cluster" "this" {
  name     = var.eks_cluster_name
  role_arn = aws_iam_role.eks_cluster.arn
  version  = var.eks_kubernetes_version

  access_config {
    authentication_mode                         = "API_AND_CONFIG_MAP"
    bootstrap_cluster_creator_admin_permissions = true
  }

  vpc_config {
    subnet_ids              = var.private_subnet_ids
    endpoint_private_access = true
    endpoint_public_access  = var.cluster_endpoint_public_access
    public_access_cidrs     = var.cluster_endpoint_public_access ? var.cluster_endpoint_public_access_cidrs : []
    security_group_ids      = [aws_security_group.eks_control_plane_access.id]
  }

  enabled_cluster_log_types = ["api", "audit", "authenticator", "controllerManager", "scheduler"]

  encryption_config {
    provider {
      key_arn = aws_kms_key.eks_secrets.arn
    }
    resources = ["secrets"]
  }

  depends_on = [
    aws_iam_role_policy_attachment.eks_cluster_policy,
    aws_iam_role_policy.eks_secrets_kms,
    aws_cloudwatch_log_group.eks_control_plane
  ]

  lifecycle {
    precondition {
      condition     = length(local.private_subnet_azs) >= 3
      error_message = "private_subnet_ids must span at least three distinct Availability Zones."
    }
    precondition {
      condition     = local.all_subnets_in_vpc
      error_message = "Every private_subnet_id must belong to the supplied vpc_id."
    }
    precondition {
      condition     = !var.cluster_endpoint_public_access || length(var.cluster_endpoint_public_access_cidrs) > 0
      error_message = "If public EKS endpoint access is enabled, provide a restrictive CIDR allow-list."
    }
  }

  tags = local.common_tags
}

resource "aws_iam_role" "eks_nodes" {
  name = "${var.eks_cluster_name}-node-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action = "sts:AssumeRole"
    }]
  })
  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "eks_node_worker" {
  role       = aws_iam_role.eks_nodes.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}

resource "aws_iam_role_policy_attachment" "eks_node_ecr" {
  role       = aws_iam_role.eks_nodes.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

resource "aws_eks_node_group" "application" {
  cluster_name    = aws_eks_cluster.this.name
  node_group_name = "${var.project_name}-application"
  node_role_arn   = aws_iam_role.eks_nodes.arn
  subnet_ids      = var.private_subnet_ids
  instance_types  = var.eks_node_instance_types
  disk_size       = var.node_disk_size
  capacity_type   = "ON_DEMAND"

  scaling_config {
    min_size     = var.node_min_size
    desired_size = var.node_desired_size
    max_size     = var.node_max_size
  }

  update_config {
    max_unavailable = 1
  }

  labels = {
    workload = "payment-service"
    pool     = "application"
  }

  depends_on = [
    aws_iam_role_policy_attachment.eks_node_worker,
    aws_iam_role_policy_attachment.eks_node_ecr,
    aws_eks_addon.vpc_cni
  ]

  tags = local.common_tags
}

resource "aws_eks_addon" "core" {
  for_each = toset(["coredns", "kube-proxy"])

  cluster_name                = aws_eks_cluster.this.name
  addon_name                  = each.value
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "PRESERVE"

  depends_on = [aws_eks_node_group.application]
}

resource "aws_eks_access_entry" "deployer" {
  for_each = local.environment_roles

  cluster_name      = aws_eks_cluster.this.name
  principal_arn     = aws_iam_role.deployer[each.key].arn
  type              = "STANDARD"
  kubernetes_groups = [each.value.group]
}

resource "aws_eks_access_entry" "additional_cluster_admin" {
  count = var.cluster_admin_role_arn != "" ? 1 : 0

  cluster_name  = aws_eks_cluster.this.name
  principal_arn = var.cluster_admin_role_arn
  type          = "STANDARD"
}


resource "aws_eks_access_policy_association" "additional_cluster_admin" {
  count = var.cluster_admin_role_arn != "" ? 1 : 0

  cluster_name  = aws_eks_cluster.this.name
  principal_arn = var.cluster_admin_role_arn
  policy_arn    = "arn:${data.aws_partition.current.partition}:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"

  access_scope {
    type = "cluster"
  }

  depends_on = [aws_eks_access_entry.additional_cluster_admin]
}


# EKS OIDC provider used by the VPC CNI and EBS CSI add-ons (IRSA).
data "tls_certificate" "eks_oidc" {
  url = aws_eks_cluster.this.identity[0].oidc[0].issuer
}

resource "aws_iam_openid_connect_provider" "eks" {
  url             = aws_eks_cluster.this.identity[0].oidc[0].issuer
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.eks_oidc.certificates[0].sha1_fingerprint]
  tags            = local.common_tags
}

locals {
  eks_oidc_issuer_hostpath = trimprefix(aws_eks_cluster.this.identity[0].oidc[0].issuer, "https://")
}

resource "aws_iam_role" "vpc_cni" {
  name = "${var.eks_cluster_name}-vpc-cni-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = { Federated = aws_iam_openid_connect_provider.eks.arn }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${local.eks_oidc_issuer_hostpath}:aud" = "sts.amazonaws.com"
          "${local.eks_oidc_issuer_hostpath}:sub" = "system:serviceaccount:kube-system:aws-node"
        }
      }
    }]
  })
  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "vpc_cni" {
  role       = aws_iam_role.vpc_cni.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonEKS_CNI_Policy"
}

resource "aws_eks_addon" "vpc_cni" {
  cluster_name                = aws_eks_cluster.this.name
  addon_name                  = "vpc-cni"
  service_account_role_arn    = aws_iam_role.vpc_cni.arn
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "PRESERVE"

  depends_on = [aws_iam_role_policy_attachment.vpc_cni]
}

resource "aws_iam_role" "ebs_csi" {
  name = "${var.eks_cluster_name}-ebs-csi-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = { Federated = aws_iam_openid_connect_provider.eks.arn }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${local.eks_oidc_issuer_hostpath}:aud" = "sts.amazonaws.com"
          "${local.eks_oidc_issuer_hostpath}:sub" = "system:serviceaccount:kube-system:ebs-csi-controller-sa"
        }
      }
    }]
  })
  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "ebs_csi" {
  role       = aws_iam_role.ebs_csi.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
}

resource "aws_eks_addon" "ebs_csi" {
  cluster_name                = aws_eks_cluster.this.name
  addon_name                  = "aws-ebs-csi-driver"
  service_account_role_arn    = aws_iam_role.ebs_csi.arn
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "PRESERVE"

  depends_on = [aws_iam_role_policy_attachment.ebs_csi, aws_eks_node_group.application]
}
