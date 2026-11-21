# Cluster autoscaler (Africa)

Copy of `../../../dalgo-staging-cluster/cluster/autoscaler/cluster-autoscaler.md` with Africa values.
Run once, after `terraform apply` in `cluster/terraform`.

**Every command uses `--kube-context dalgo-staging-af`.** Same release name/namespace as Mumbai, so the wrong
context would change Mumbai's autoscaler.

## Install

```bash
helm repo add autoscaler https://kubernetes.github.io/autoscaler
helm repo update autoscaler

helm --kube-context dalgo-staging-af upgrade --install cluster-autoscaler autoscaler/cluster-autoscaler \
  -n kube-system \
  --version 9.59.0 \
  --set image.tag=v1.36.1 \
  --set autoDiscovery.clusterName=dalgo-staging-af-cluster \
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

- `autoDiscovery.clusterName=dalgo-staging-af-cluster`: the real cluster name. Wrong name =
  0 node groups found, autoscaling silently never happens.
- `rbac.serviceAccount.name=cluster-autoscaler`: Terraform's Pod Identity association links
  this name to the IAM role (`dalgo-staging-af-eks-cluster-autoscaler`). Wrong name = no AWS credentials.

## Check

```bash
# pod running
kubectl --context dalgo-staging-af -n kube-system get deploy -l app.kubernetes.io/name=aws-cluster-autoscaler

# node groups it manages: must list all 3 dalgo-staging-af-node-group-* ASGs
kubectl --context dalgo-staging-af -n kube-system get cm cluster-autoscaler-status -o jsonpath='{.data.status}' | grep 'name: eks-'

# no credential / permission errors (should print nothing)
kubectl --context dalgo-staging-af -n kube-system logs -l app.kubernetes.io/name=aws-cluster-autoscaler --tail=300 \
  | grep -iE 'forbidden|denied|credential|imds|unknown flag'
```

## Notes

- **vCPU quota:** af-south-1 on-demand standard quota is 10 vCPU (t4g = 2 vCPU each) = 5 nodes max, below the
  node groups' combined `max_size`. Past 5 nodes, scale-ups fail (`VcpuLimitExceeded` in the ASG activity) and
  pods stay Pending. Fine for the test; raise the quota or lower `max_size` if it bites.
- **Version:** autoscaler minor = Kubernetes minor (cluster 1.36 -> v1.36.x).
- **What scales:** each managed node group between its `min_size` and `max_size`
  (`cluster/terraform/variables.tf`, `node_groups`).
- **How node groups are found:** EKS tags every managed node group's ASG with
  `k8s.io/cluster-autoscaler/enabled` and `k8s.io/cluster-autoscaler/dalgo-staging-af-cluster`.
- **Who owns what:** Terraform creates the IAM role, policy and Pod Identity association
  (`kube-system/cluster-autoscaler`); Helm creates the Deployment, ServiceAccount and RBAC.
