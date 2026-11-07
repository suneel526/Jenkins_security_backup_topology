#!/usr/bin/env bash
set -euo pipefail
for cmd in aws terraform jq; do
  command -v "$cmd" >/dev/null 2>&1 || { echo "Missing command: $cmd" >&2; exit 1; }
done
REGION=$(aws configure get region 2>/dev/null || true)
if [[ -n "$REGION" && "$REGION" != "ap-south-2" ]]; then
  echo "Warning: AWS CLI configured region is $REGION; expected ap-south-2." >&2
fi
aws sts get-caller-identity
aws ec2 describe-availability-zones --region ap-south-2 --all --query 'AvailabilityZones[?State==`available`].ZoneName' --output table
echo "Prerequisite CLI check complete. Verify ap-south-2 is enabled and confirm VPC/subnet routing separately."
