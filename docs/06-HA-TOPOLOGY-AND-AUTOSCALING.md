# Topology spread, HA and autoscaling

## Topology spread constraints in the app chart

The chart uses two constraints:

- `topology.kubernetes.io/zone`, `maxSkew: 1`, `whenUnsatisfiable: DoNotSchedule`: keep eligible replicas balanced across zones. With three replicas and three schedulable zones, the desired layout is one replica per AZ.
- `kubernetes.io/hostname`, `maxSkew: 1`, `whenUnsatisfiable: ScheduleAnyway`: prefer spreading replicas across nodes within the zone distribution.

`maxSkew` is the maximum permitted difference between the number of matching Pods in eligible topology domains. `topologyKey` names the node label that defines a domain. `whenUnsatisfiable` determines whether a Pod is blocked (`DoNotSchedule`) or the scheduler may still place it (`ScheduleAnyway`). `labelSelector` counts only Pods matching the selected application labels.

The scheduler can only place Pods where nodes exist and resources/taints/affinity allow placement. Three subnets do not guarantee three running nodes; keep at least three nodes, one in each AZ in practice, and ensure node autoscaling/instance quotas can replace failed capacity.

## PDB and HPA are different controls

- PDB (`minAvailable: 2`) limits voluntary disruption to one of three healthy replicas under normal conditions. It does not prevent involuntary AZ/node failures and may block a drain if fewer than two are healthy.
- HPA scales application Pod replicas based on resource metrics. It requires the metrics API (metrics-server; install with `monitoring/install-metrics-server.sh` after selecting a tested version) and resource requests on containers.
- Managed node group scaling or Cluster Autoscaler/Karpenter is needed to add EC2 capacity when Pods cannot schedule. HPA alone does not create nodes.

## Verify placement

```bash
kubectl get nodes -L topology.kubernetes.io/zone,kubernetes.io/hostname
kubectl get pods -n payment-service-dev -l app.kubernetes.io/part-of=payment-service -o wide
kubectl describe pod -n payment-service-dev <pod-name>
```

Check scheduler events for `didn't match pod topology spread constraints`, insufficient CPU/memory, taints or node affinity.

## Autoscaling extension

This starter creates an EKS managed node group with min/desired/max sizes. It does not install Cluster Autoscaler or Karpenter because those require additional version compatibility, IAM/Pod Identity, node discovery and disruption design. Add one (not both by default) after validating the current EKS version and AWS-supported installation procedure. Keep scale-down policies conservative for stateful/critical workloads.

## Stateful workloads

EBS volumes are AZ-scoped. A Pod with a single EBS PVC cannot be freely rescheduled to another AZ without a storage replication/restore strategy. Use Multi-AZ databases, application-level replication, EFS where shared file semantics are appropriate, or tested EBS snapshot/restore workflows. Do not apply stateless Pod spread as a substitute for data replication.
