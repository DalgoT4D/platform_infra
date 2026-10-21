# demosuperset

Release name `demosuperset`, namespace `superset`. Runs on the dedicated `supersets` node group
and is exposed on the internet-facing ALB at demosuperset.dalgo.org.

## Install

```bash
helm repo add superset https://apache.github.io/superset
helm repo update superset

# namespace first: the env secret below goes into it
kubectl create namespace superset

# env: copy superset-env.example.yaml, fill in, never commit the filled file
kubectl apply -f superset-env.yaml

helm upgrade --install demosuperset superset/superset -n superset --values values6.0.0.yaml --version 0.14.1
```

Uninstall:

```bash
helm uninstall demosuperset -n superset
```

Port forward (bypass the ALB):

```bash
kubectl port-forward service/demosuperset 8088:8088 -n superset
```
