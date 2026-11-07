#!/usr/bin/env bash
set -euo pipefail

: "${PROMETHEUS_CHART_VERSION:?Set a tested kube-prometheus-stack chart version explicitly}"
NAMESPACE="${MONITORING_NAMESPACE:-monitoring}"

helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update
kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

helm upgrade --install monitoring prometheus-community/kube-prometheus-stack \
  --namespace "$NAMESPACE" \
  --version "$PROMETHEUS_CHART_VERSION" \
  --values "$(dirname "$0")/kube-prometheus-stack-values.yaml" \
  --wait --timeout 15m
