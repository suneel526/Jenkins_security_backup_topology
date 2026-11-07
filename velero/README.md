# Optional Velero backup for EKS application namespaces and EBS volumes

1. Set `enable_velero_backup=true` and a globally unique `velero_backup_bucket_name` in platform `terraform.tfvars`.
2. Apply Terraform and capture `velero_backup_bucket_name` and `velero_iam_role_arn` outputs.
3. Replace the two placeholders in `values.yaml`.
4. Select and pin a Velero Helm chart version compatible with your cluster and plugin. Set `VELERO_CHART_VERSION` and run `./velero/install-velero.sh`.
5. Apply `kubectl apply -f velero/daily-schedule.yaml`.
6. Verify backups with `velero backup get`, inspect logs, and test restore to a non-production namespace/cluster.

This configuration uses Velero's AWS plugin for S3 backup storage and EBS snapshots. Review the plugin version, chart values and IAM policy against the exact selected release before production. The example policy includes EC2 snapshot operations with `Resource: "*"`; tighten it with supported resource/tag conditions where practical. If EBS volumes use customer-managed KMS keys other than the key created here, grant the Velero role the exact required KMS permissions on those keys as well.

Velero backs up Kubernetes objects and snapshots eligible volumes; it does not replace database-native replication, PITR or a tested application-consistent database backup. Verify that the EBS CSI driver is healthy and that workload volumes use a supported StorageClass.
