# Cluster autoscaler (Africa)

Copy of `../../../dalgo-staging-cluster-africa/cluster/autoscaler/cluster-autoscaler.md` with prod Africa values.
Run once, after `terraform apply` in `cluster/terraform`.

**Every command uses `--kube-context dalgo-prod-af`.** Same release name/namespace as Mumbai prod, so the wrong
context would change Mumbai prod's autoscaler.

## Install

```bash
helm repo add autoscaler https://kubernetes.github.io/autoscaler
helm repo update autoscaler

helm --kube-context dalgo-prod-af upgrade --install cluster-autoscaler autoscaler/cluster-autoscaler \
  -n kube-system \
  --version 9.59.0 \
  --set image.tag=v1.36.1 \
  --set autoDiscovery.clusterName=dalgo-prod-af-cluster \
  --set awsRegion=af-south-1 \
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

- `autoDiscovery.clusterName=dalgo-prod-af-cluster`: the real cluster name. Wrong name =
  0 node groups found, autoscaling silently never happens.
- `rbac.serviceAccount.name=cluster-autoscaler`: Terraform's Pod Identity association links
  this name to the IAM role (`dalgo-prod-af-eks-cluster-autoscaler`). Wrong name = no AWS credentials.

## Check

```bash
# pod running
kubectl --context dalgo-prod-af -n kube-system get deploy -l app.kubernetes.io/name=aws-cluster-autoscaler

# node groups it manages: must list all 3 dalgo-prod-af-node-group-* ASGs
kubectl --context dalgo-prod-af -n kube-system get cm cluster-autoscaler-status -o jsonpath='{.data.status}' | grep 'name: eks-'

# no credential / permission errors (should print nothing)
kubectl --context dalgo-prod-af -n kube-system logs -l app.kubernetes.io/name=aws-cluster-autoscaler --tail=300 \
  | grep -iE 'forbidden|denied|credential|imds|unknown flag'
```

## Notes

- **vCPU quota:** a newly enabled af-south-1 usually starts at 10 on-demand standard vCPU (t4g.large/medium = 2 each)
  = 5 nodes, below the node groups' combined `max_size` (11). Past that, scale-ups fail (`VcpuLimitExceeded` in the
  ASG activity) and pods stay Pending. For prod: request an increase (quota L-1216C47A, e.g. 32) right after
  enabling the region, before the first apply.
- **Version:** autoscaler minor = Kubernetes minor (cluster 1.36 -> v1.36.x).
- **What scales:** each managed node group between its `min_size` and `max_size`
  (`cluster/terraform/variables.tf`, `node_groups`).
- **How node groups are found:** EKS tags every managed node group's ASG with
  `k8s.io/cluster-autoscaler/enabled` and `k8s.io/cluster-autoscaler/dalgo-prod-af-cluster`.
- **Who owns what:** Terraform creates the IAM role, policy and Pod Identity association
  (`kube-system/cluster-autoscaler`); Helm creates the Deployment, ServiceAccount and RBAC.
