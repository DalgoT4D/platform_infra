# Cluster autoscaler

Run once per new cluster, after `terraform apply` in `cluster/terraform`.

## Install

```bash
helm repo add autoscaler https://kubernetes.github.io/autoscaler
helm repo update autoscaler

helm upgrade --install cluster-autoscaler autoscaler/cluster-autoscaler \
  -n kube-system \
  --version 9.59.0 \
  --set image.tag=v1.36.1 \
  --set autoDiscovery.clusterName=dalgo-staging-cluster \
  --set awsRegion=ap-south-1 \
  --set rbac.serviceAccount.create=true \
  --set rbac.serviceAccount.name=cluster-autoscaler \
  --set extraArgs.skip-nodes-with-local-storage=false \
  --set extraArgs.expander=least-waste \
  --set resources.requests.cpu=100m \
  --set resources.requests.memory=500Mi \
  --set resources.limits.cpu=200m \
  --set resources.limits.memory=1Gi
```

Two values must be exact:

- `autoDiscovery.clusterName=dalgo-staging-cluster`: the real cluster name. Wrong name =
  0 node groups found, autoscaling silently never happens.
- `rbac.serviceAccount.name=cluster-autoscaler`: Terraform's Pod Identity association links
  this name to the IAM role. Wrong name = no AWS credentials (IMDS timeout in the logs).

## Check

```bash
# pod running
kubectl -n kube-system get deploy -l app.kubernetes.io/name=aws-cluster-autoscaler

# node groups it manages: must list all 4 staging-node-group-* ASGs
kubectl -n kube-system get cm cluster-autoscaler-status -o jsonpath='{.data.status}' | grep 'name: eks-'

# no credential / permission errors (should print nothing)
kubectl -n kube-system logs -l app.kubernetes.io/name=aws-cluster-autoscaler --tail=300 \
  | grep -iE 'forbidden|denied|credential|imds|unknown flag'
```

## Test (optional)

```bash
kubectl create deployment big --image=busybox --replicas=6 -- sleep 3600
kubectl set resources deployment big --requests=cpu=900m
kubectl get events -A --field-selector source=cluster-autoscaler   # expect TriggeredScaleUp
kubectl delete deployment big                                       # extra nodes removed ~10 min later
```

## Notes

- **Version:** the autoscaler's minor version should match Kubernetes (cluster 1.36 -> v1.36.x).
- **What scales:** each managed node group between its `min_size` and `max_size`
  (`cluster/terraform/variables.tf`, `node_groups`).
- **How node groups are found:** EKS tags every managed node group's ASG automatically with
  `k8s.io/cluster-autoscaler/enabled` and `k8s.io/cluster-autoscaler/dalgo-staging-cluster`;
  the `--node-group-auto-discovery` flag matches those tags.
- **Who owns what:** Terraform creates the IAM role, its policy and the Pod Identity association
  (`kube-system/cluster-autoscaler`); no annotation on the service account is needed. Helm creates
  the Deployment, ServiceAccount and RBAC.
- **History:** replaces the `kubernetes_deployment` / service account / RBAC resources in the old
  Terraform (`dalgo-staging-cluster/cluster/tf/cluster.tf`, `dalgo-staging-cluster/airbyte/cluster/update_cluster.tf`).
  Same flags as old staging; image moved from v1.27.3 to v1.36.1.
