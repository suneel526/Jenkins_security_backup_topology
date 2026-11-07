#!/usr/bin/env bash
set -euo pipefail

: "${METRICS_SERVER_VERSION:?Set a tested metrics-server release version explicitly}"
MANIFEST_URL="https://github.com/kubernetes-sigs/metrics-server/releases/download/${METRICS_SERVER_VERSION}/components.yaml"

echo "Installing metrics-server ${METRICS_SERVER_VERSION}"
curl --fail --silent --show-error --location "$MANIFEST_URL" | kubectl apply -f -
kubectl rollout status deployment/metrics-server -n kube-system --timeout=5m
