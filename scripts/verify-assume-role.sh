#!/usr/bin/env bash
set -euo pipefail

BASE_ARN=$(aws sts get-caller-identity --query Arn --output text)
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

if [[ "$BASE_ARN" != *"assumed-role/Jenkins-Base-Role/"* ]]; then
  echo "Expected Jenkins-Base-Role, received: $BASE_ARN" >&2
  exit 1
fi

for env in dev qa prod; do
  role="payment-service-${env}-deployer"
  arn="arn:aws:iam::${ACCOUNT_ID}:role/${role}"
  echo "Testing $role"
  json=$(aws sts assume-role --role-arn "$arn" --role-session-name "verify-${env}-$(date +%s)" --duration-seconds 900 --output json)
  export AWS_ACCESS_KEY_ID=$(printf '%s' "$json" | jq -r '.Credentials.AccessKeyId')
  export AWS_SECRET_ACCESS_KEY=$(printf '%s' "$json" | jq -r '.Credentials.SecretAccessKey')
  export AWS_SESSION_TOKEN=$(printf '%s' "$json" | jq -r '.Credentials.SessionToken')
  aws sts get-caller-identity
  unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN json
done

echo "All three same-account role assumptions succeeded."
