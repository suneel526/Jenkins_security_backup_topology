#!/usr/bin/env bash
set -euo pipefail
# Run only with an authorized Kubernetes administrator identity after Terraform creates the cluster.
kubectl apply -f "$(dirname "$0")/../k8s/base/namespaces-and-rbac.yaml"
kubectl apply -f "$(dirname "$0")/../k8s/base/storage-class-gp3.yaml"
for env in dev qa prod; do
  ns="payment-service-${env}"
  echo "Namespace $ns"
  kubectl get namespace "$ns"
  kubectl get rolebinding payment-service-helm-deployer -n "$ns"
done
