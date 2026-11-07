# Architecture and design decisions

## Logical topology

```text
                         ONE AWS ACCOUNT — ap-south-2
┌─────────────────────────────────────────────────────────────────────┐
│ Existing VPC (reused; IDs supplied by operator)                     │
│                                                                     │
│  Existing Jenkins EC2                                               │
│  ├─ Existing CI job remains unchanged                               │
│  ├─ EC2 Instance Profile: Jenkins-Instance-Profile                 │
│  └─ IAM role: Jenkins-Base-Role                                     │
│          │ STS AssumeRole                                           │
│          ├──────────────┬────────────────┬────────────────┐          │
│          ▼              ▼                ▼                │          │
│  payment-service-   payment-service-  payment-service-    │          │
│  dev-deployer       qa-deployer       prod-deployer       │          │
│          │              │                │                │          │
│          └──────────────┴────────────────┴────────────────┘          │
│                        EKS private API endpoint                      │
│                                                                     │
│  Private subnets in 3 distinct AZs                                 │
│    AZ-A: EKS worker node(s)                                         │
│    AZ-B: EKS worker node(s)                                         │
│    AZ-C: EKS worker node(s)                                         │
│                                                                     │
│  Namespaces: payment-service-dev / -qa / -prod                      │
│  Each deployer role maps to one Kubernetes group + namespace Role   │
│                                                                     │
│  ECR: payment-service immutable image repository
│  EBS CSI add-on: IRSA role for gp3 persistent storage                    │
│  S3: versioned Terraform state (bootstrap-created)                  │
│  AWS Backup: optional EC2/EBS backup for existing Jenkins           │
└─────────────────────────────────────────────────────────────────────┘
```

## Trust and authorization chain

1. EC2 service assumes `Jenkins-Base-Role` through the instance profile.
2. Jenkins uses STS `AssumeRole` to obtain temporary credentials for exactly one environment role.
3. That target role has an EKS access entry mapped to one Kubernetes group.
4. A namespace RoleBinding grants that group permission only in the matching namespace.
5. Kubernetes RBAC is the final resource authorization layer for Helm operations. AWS IAM permission to call `eks:DescribeCluster` does not itself grant Kubernetes admin access.

## Single account, separate environments

This delivers IAM and Kubernetes namespace separation inside one AWS account. It is not equivalent to separate AWS accounts: billing, account-level quotas, some control-plane settings, and some administrative blast radius remain shared. For stronger production isolation, use a separate AWS account for production when the organization can support it.

## High availability

- EKS control plane availability is AWS-managed across multiple AZs.
- The managed node group uses private subnets in at least three distinct AZs.
- Application replicas use `topology.kubernetes.io/zone` and `kubernetes.io/hostname` constraints.
- A PDB protects against voluntary disruptions; it does not protect against all simultaneous failures.
- HPA scales Pods based on metrics; a node autoscaling solution must also provide node capacity. This starter uses a fixed min/desired/max managed node group. Add Cluster Autoscaler or Karpenter after validating node labels, IAM and disruption settings.
- A Deployment topology policy cannot make a single-AZ database or one EBS volume highly available. Stateful systems need their own replication, storage and recovery design.

## Existing Jenkins preservation

The Jenkins controller stays on its existing EC2 instance and in its existing VPC. This project does not create a second Jenkins server. The role/profile change is a controlled cutover, not an automatic resource replacement. Export JCasC/plugin/job settings and snapshot EBS before changes. The original CI job remains untouched; a new CD job is cloned/created separately.

## Region details

The AWS provider uses `ap-south-2`. IAM is an AWS global service; IAM roles and policies are not regional infrastructure. The EKS cluster, node group, ECR repository, backup vault and other regional services are created in the configured region. Ensure `ap-south-2` is enabled in the AWS account and verify service/quota availability before provisioning.
