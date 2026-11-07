#!/usr/bin/env bash
set -euo pipefail

# Run on the existing Jenkins EC2 instance. Uses IMDSv2 and does not print IP addresses.
IMDS="http://169.254.169.254/latest"
TOKEN=$(curl --fail --silent --show-error -X PUT "$IMDS/api/token" \
  -H 'X-aws-ec2-metadata-token-ttl-seconds: 21600')
meta() { curl --fail --silent --show-error -H "X-aws-ec2-metadata-token: $TOKEN" "$IMDS/meta-data/$1"; }

INSTANCE_ID=$(meta instance-id)
REGION=$(meta placement/region)
AZ=$(meta placement/availability-zone)
MAC=$(meta network/interfaces/macs/ | head -n1 | tr -d '/')
VPC_ID=$(meta "network/interfaces/macs/${MAC}/vpc-id")
SUBNET_ID=$(meta "network/interfaces/macs/${MAC}/subnet-id")
SG_IDS=$(meta "network/interfaces/macs/${MAC}/security-group-ids" | tr '\n' ' ')
PROFILE_ARN="not-attached"
if curl --silent --fail -H "X-aws-ec2-metadata-token: $TOKEN" "$IMDS/meta-data/iam/info" >/tmp/jenkins-imds-iam-info.json; then
  PROFILE_ARN=$(python3 -c 'import json;print(json.load(open("/tmp/jenkins-imds-iam-info.json")).get("InstanceProfileArn","unknown"))')
fi
rm -f /tmp/jenkins-imds-iam-info.json

cat <<EOF
Existing Jenkins EC2 inspection
Instance ID:       $INSTANCE_ID
Region:            $REGION
Availability Zone: $AZ
VPC ID:            $VPC_ID
Subnet ID:         $SUBNET_ID
Security Group IDs:$SG_IDS
Instance Profile:  $PROFILE_ARN

No public/private IP address is required for the IAM trust relationship.
EOF
