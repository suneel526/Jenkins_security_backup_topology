# Required operator inputs

Populate these values from your AWS account and existing Jenkins EC2. Never guess them.

| Input | Where to obtain it | Used by |
|---|---|---|
| AWS account ID | `aws sts get-caller-identity --query Account --output text` | Display/verification; Terraform discovers it dynamically |
| Jenkins instance ID | EC2 Console or `scripts/inspect-jenkins-ec2.sh` | Optional AWS Backup selection |
| Jenkins current instance profile | EC2 Console → Instance → Security | Safe IAM migration |
| Jenkins VPC ID | Instance details/metadata script | Confirms VPC reuse |
| Jenkins security group ID | EC2 Console → Security | EKS API SG ingress source |
| Private subnet IDs | VPC Console; confirm private routing and AZs | EKS cluster and managed node group |
| Kubernetes version | EKS supported version matrix in ap-south-2 | `eks_kubernetes_version` |
| Jenkins job type/name | Jenkins job configuration | Safe copy/clone process |
| Jenkins API token | Jenkins user profile; store in shell secret manager | Export/clone scripts |
| Application port/health paths | Application owner/repo | Helm values |
| ECR repo / CI output digest | CI pipeline | CD immutable image input |
| Existing bucket names, if any | S3 Console | Do not create duplicates |

## Preflight commands

```bash
aws sts get-caller-identity
aws ec2 describe-instances --instance-ids i-REPLACE --region ap-south-2 \
  --query 'Reservations[].Instances[].{VpcId:VpcId,SubnetId:SubnetId,Az:Placement.AvailabilityZone,Profile:IamInstanceProfile.Arn,SecurityGroups:SecurityGroups[].GroupId}'
aws ec2 describe-subnets --subnet-ids subnet-aaa subnet-bbb subnet-ccc --region ap-south-2 \
  --query 'Subnets[].{Subnet:SubnetId,Vpc:VpcId,Az:AvailabilityZone,PublicIpMap:MapPublicIpOnLaunch}'
aws eks describe-cluster --name REPLACE_IF_EXISTS --region ap-south-2
```

The last command is only a check for an existing cluster. The Terraform in this repository creates a cluster with the name configured in `terraform.tfvars`; do not use the same name as an existing cluster unless you import and manage that cluster intentionally.
