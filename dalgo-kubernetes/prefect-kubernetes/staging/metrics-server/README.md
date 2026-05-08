# Metrics Server (Staging)

Required for HPA (Horizontal Pod Autoscaler) to function.
Provides the `metrics.k8s.io` API that HPA reads CPU/memory utilization from.

## Install

```bash
helm repo add metrics-server https://kubernetes-sigs.github.io/metrics-server/
helm repo update

helm install metrics-server metrics-server/metrics-server \
  -n kube-system \
  -f values.yaml
```

## Upgrade

```bash
helm upgrade metrics-server metrics-server/metrics-server \
  -n kube-system \
  -f values.yaml
```

## Uninstall

```bash
helm uninstall metrics-server -n kube-system
```

## Verify

```bash
# Check if metrics-server pod is running
kubectl get pods -n kube-system | grep metrics-server

# Check if metrics API is available
kubectl top nodes
kubectl top pods
```
