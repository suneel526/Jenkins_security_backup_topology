variable "aws_region" {
  description = "AWS region; this project is configured for Hyderabad"
  type        = string
  default     = "ap-south-2"

  validation {
    condition     = var.aws_region == "ap-south-2"
    error_message = "This project is intentionally configured for ap-south-2 (Hyderabad)."
  }
}

variable "project_name" {
  type        = string
  description = "Short project identifier used in resource names and tags"
  default     = "payment-service"
}

variable "vpc_id" {
  type        = string
  description = "Existing VPC ID that contains the Jenkins EC2 instance and selected private EKS subnets"
}

variable "jenkins_security_group_id" {
  type        = string
  description = "Security group ID attached to the existing Jenkins EC2 instance; must be in vpc_id"
}

variable "jenkins_instance_id" {
  type        = string
  description = "Existing Jenkins EC2 instance ID; required only when enable_jenkins_backup=true"
  default     = ""
}

variable "private_subnet_ids" {
  type        = list(string)
  description = "At least three private subnet IDs in three distinct AZs, all within vpc_id"

  validation {
    condition     = length(var.private_subnet_ids) >= 3
    error_message = "Provide at least three private subnet IDs for three-AZ EKS high availability."
  }
}

variable "eks_cluster_name" {
  type        = string
  description = "Name of the new EKS cluster; do not reuse the name of an unmanaged existing cluster"
  default     = "payment-service-eks"
}

variable "eks_kubernetes_version" {
  type        = string
  description = "Select a Kubernetes version currently supported by EKS in ap-south-2; no stale default is imposed"
}

variable "eks_node_instance_types" {
  type        = list(string)
  description = "EC2 instance types for the managed node group; verify regional availability and workload sizing"
  default     = ["t3.large"]
}

variable "node_min_size" {
  type    = number
  default = 3
}

variable "node_desired_size" {
  type    = number
  default = 3
}

variable "node_max_size" {
  type    = number
  default = 9
}

variable "node_disk_size" {
  type        = number
  description = "Managed node root EBS volume size in GiB"
  default     = 50
}

variable "cluster_endpoint_public_access" {
  type        = bool
  description = "Keep false for a private EKS endpoint. Enable only with a restricted CIDR list and an approved network design."
  default     = false
}

variable "cluster_endpoint_public_access_cidrs" {
  type        = list(string)
  description = "Restrictive public endpoint CIDRs; required only when public access is enabled"
  default     = []

  validation {
    condition     = length(var.cluster_endpoint_public_access_cidrs) == 0 || alltrue([for cidr in var.cluster_endpoint_public_access_cidrs : can(cidrhost(cidr, 0))])
    error_message = "Every public endpoint CIDR must be valid CIDR notation."
  }
}

variable "cluster_admin_role_arn" {
  type        = string
  description = "Optional additional IAM role ARN to register as an EKS access entry for initial cluster administration"
  default     = ""
}

variable "ecr_repository_name" {
  type        = string
  description = "Immutable ECR repository used by the existing CI pipeline and new CD pipeline"
  default     = "payment-service"
}

variable "enable_jenkins_backup" {
  type        = bool
  description = "Create AWS Backup plan/selection for the existing Jenkins EC2 instance"
  default     = false

  validation {
    condition     = !var.enable_jenkins_backup || length(var.jenkins_instance_id) > 0
    error_message = "Set jenkins_instance_id when enable_jenkins_backup is true."
  }
}

variable "backup_daily_retention_days" {
  type        = number
  description = "Daily EC2 backup retention"
  default     = 35
}

variable "backup_weekly_retention_days" {
  type        = number
  description = "Weekly EC2 backup retention"
  default     = 365
}

variable "jenkins_home_backup_bucket_name" {
  type        = string
  description = "Optional globally unique private S3 bucket for encrypted JENKINS_HOME archives; leave blank to skip bucket creation"
  default     = ""
}

variable "enable_velero_backup" {
  type        = bool
  description = "Create a Velero S3 backup bucket and IRSA role for Kubernetes backups"
  default     = false

  validation {
    condition     = !var.enable_velero_backup || length(var.velero_backup_bucket_name) > 0
    error_message = "Set velero_backup_bucket_name when enable_velero_backup is true."
  }
}

variable "velero_backup_bucket_name" {
  type        = string
  description = "Globally unique S3 bucket for Velero backups; required when enable_velero_backup=true"
  default     = ""
}


variable "jenkins_home_backup_retention_days" {
  type        = number
  description = "Days to retain JENKINS_HOME archive objects before expiration"
  default     = 90
}
