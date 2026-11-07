data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

data "aws_subnet" "private" {
  for_each = toset(var.private_subnet_ids)
  id       = each.value
}

locals {
  account_id = data.aws_caller_identity.current.account_id
  cluster_arn = "arn:${data.aws_partition.current.partition}:eks:${var.aws_region}:${local.account_id}:cluster/${var.eks_cluster_name}"

  environment_roles = {
    dev = {
      name      = "payment-service-dev-deployer"
      namespace = "payment-service-dev"
      group     = "payment-service-dev-deployers"
    }
    qa = {
      name      = "payment-service-qa-deployer"
      namespace = "payment-service-qa"
      group     = "payment-service-qa-deployers"
    }
    prod = {
      name      = "payment-service-prod-deployer"
      namespace = "payment-service-prod"
      group     = "payment-service-prod-deployers"
    }
  }

  private_subnet_azs = distinct([for subnet in values(data.aws_subnet.private) : subnet.availability_zone])
  all_subnets_in_vpc = alltrue([for subnet in values(data.aws_subnet.private) : subnet.vpc_id == var.vpc_id])
  common_tags = {
    Project   = var.project_name
    ManagedBy = "Terraform"
    Region    = var.aws_region
  }
}
