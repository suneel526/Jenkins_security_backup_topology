# Claude master prompt — extend this project without breaking the live CI pipeline

Act as a senior AWS Solutions Architect, DevOps/SRE engineer, Terraform engineer, Jenkins administrator and Kubernetes/EKS platform engineer.

Build on this repository and its fixed constraints:

- One AWS account only, region `ap-south-2` (Hyderabad).
- Jenkins already runs on an existing EC2 instance; do not create or replace that Jenkins instance.
- The existing CI pipeline works and must remain unchanged. Create a separate CD job and use safe export/clone methods.
- Jenkins obtains AWS credentials using an EC2 instance profile and assumes same-account IAM deployment roles for `dev`, `qa`, and `prod`.
- Use Terraform for AWS infrastructure and IAM, EKS with private nodes across at least three AZs, ECR immutable images, Helm for deployment, Kubernetes namespaces/RBAC, topology spread constraints, PDB/HPA/probes, security controls, monitoring, and backup/restore procedures.

Do not invent account IDs, resource IDs, subnet IDs, existing job names/types, Jenkins credentials, Kubernetes versions, or regionally unavailable instance types. Make unknowns explicit inputs. Before changing the existing Jenkins instance profile, inspect the current role and preserve permissions used by CI. Never print or commit secret values. Do not grant cluster-admin to application deployment roles. Distinguish IAM permissions from Kubernetes RBAC. Do not imply topology spread alone guarantees HA. Include exact file names, valid complete code, verification commands, expected outputs and rollback steps. Validate Terraform formatting/syntax, YAML, shell syntax, Helm chart rendering and Jenkins pipeline syntax where tools are available. Clearly label anything that requires operator-specific configuration.

When adding features, update README, architecture, implementation runbook, troubleshooting and all affected configuration examples. Keep the original CI job untouched; do not overwrite a pre-existing CD target job. Ask for missing required inputs only when genuinely necessary; otherwise use explicit placeholders and document them.
