#!/usr/bin/env bash
set -euo pipefail

# Optional protected JENKINS_HOME archive. This contains highly sensitive credential/key material.
# Prefer AWS Backup EC2/EBS recovery points for DR; a live tar is not guaranteed application-consistent.
: "${JENKINS_HOME:?Set JENKINS_HOME, e.g. /var/lib/jenkins}"
: "${BACKUP_BUCKET:?Set BACKUP_BUCKET to the private versioned bucket created by Terraform}"
: "${BACKUP_KMS_KEY_ID:?Set BACKUP_KMS_KEY_ID to the Terraform jenkins_backup_kms_key_arn output}"
command -v aws >/dev/null
command -v tar >/dev/null

STAMP=$(date -u +%Y%m%dT%H%M%SZ)
HOST=$(hostname -s)
JENKINS_PARENT=$(dirname "$JENKINS_HOME")
JENKINS_DIR=$(basename "$JENKINS_HOME")
OBJECT="s3://${BACKUP_BUCKET}/jenkins-home/${STAMP}/${HOST}-jenkins-home.tar.gz"

# Stream the archive directly to S3 so an unencrypted archive is not left on local disk.
# This includes secrets/master.key and secrets/hudson.util.Secret; protect the destination tightly.
tar --warning=no-file-changed --xattrs --acls \
  --exclude="${JENKINS_DIR}/workspace" \
  --exclude="${JENKINS_DIR}/caches" \
  -czf - -C "$JENKINS_PARENT" "$JENKINS_DIR" | \
  aws s3 cp - "$OBJECT" \
    --region ap-south-2 \
    --sse aws:kms \
    --sse-kms-key-id "$BACKUP_KMS_KEY_ID" \
    --only-show-errors

echo "Encrypted archive uploaded to $OBJECT. Verify S3 versioning, KMS key policy, access controls and restore procedure."
