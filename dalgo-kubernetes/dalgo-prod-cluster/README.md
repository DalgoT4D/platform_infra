# dalgo-prod-cluster

Production EKS cluster (ap-south-1, VPC `dalgo-prod-vpc` / `vpc-060665f96234a5997`).
Runs the **production data platform**: Airbyte + Prefect + monitoring.
(Production Superset is a *separate* cluster — see `dalgo-superset-production-cluster`.)

## What runs here

| Namespace | What | Exposure |
|-----------|------|----------|
| `airbyte` | Airbyte ingestion stack | **internal ALB** (`airbyte-internal-ingress`, class `alb`) |
| `prefect` | in-cluster `prefect-worker` (Prefect server runs externally) | none |
| `monitoring` | kube-prometheus-stack (Grafana, Prometheus, Alertmanager) | Grafana via its own internet-facing **ALB** (`dalgo-prod-grafana-alb`, TLS) at `grafana-airbyte.dalgo.org` |

## Ingress / load balancers
- Single IngressClass: **`alb`** (AWS LB Controller).
- LBs: Airbyte internal ALB · Grafana internet-facing ALB (`dalgo-prod-grafana-alb`) — standalone ingress `monitoring/grafana-airbyte-ingress.yaml`.

## Folder structure
```
airbyte/      Airbyte cluster (eksctl tf) + helm values
prefect/      prefect-worker helm values + metrics-server
monitoring/   kube-prometheus-stack (grafana) values + PV/PVCs
```
