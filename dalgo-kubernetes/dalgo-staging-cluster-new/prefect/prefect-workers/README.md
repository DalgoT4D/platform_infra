# Prefect worker

The Prefect server runs on a standalone EC2 box. The cluster reaches it through a ClusterIP
service with a manual endpoint; only the worker runs in-cluster.

## Install

```bash
# namespace first: the service and endpoint below go into it
kubectl create namespace prefect

# service for the external Prefect server
kubectl apply -f prefect-external-service.yaml

# endpoint mapping that service to the server's IP:
# copy prefect-external-service-endpoint.example.yaml, fill in, never commit the filled file
kubectl apply -f prefect-external-service-endpoint.yaml

# worker
helm repo add prefect https://prefecthq.github.io/prefect-helm
helm repo update prefect
helm upgrade --install prefect-worker prefect/prefect-worker -n prefect -f values3.1.15.yaml --version 2025.1.30204105
```

Uninstall:

```bash
helm uninstall prefect-worker -n prefect
```
