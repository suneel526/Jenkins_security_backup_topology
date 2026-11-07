#!/usr/bin/env bash
set -euo pipefail

: "${VELERO_CHART_VERSION:?Set a chart version compatible with the installed Velero plugin and Kubernetes version}"

helm repo add vmware-tanzu https://vmware-tanzu.github.io/helm-charts
helm repo update
kubectl create namespace velero --dry-run=client -o yaml | kubectl apply -f -

helm upgrade --install velero vmware-tanzu/velero \
  --namespace velero \
  --version "$VELERO_CHART_VERSION" \
  --values "$(dirname "$0")/values.yaml" \
  --wait --timeout 10m

kubectl rollout status deployment/velero -n velero --timeout=5m
