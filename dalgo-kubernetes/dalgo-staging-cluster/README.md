# dalgo-staging-cluster

Staging EKS cluster (ap-south-1, VPC `dalgo-staging-vpc` / `vpc-06f43a5a006ddeea0`).
Hosts the **full staging data platform**: Airbyte, Prefect, Superset, and monitoring.

## What runs here

| Namespace | What | Exposure |
|-----------|------|----------|
| `airbyte` | Airbyte ingestion stack | **internal ALB** (`airbyte-internal-ingress`, class `alb`) |
| `prefect` | in-cluster `prefect-worker` (Prefect **server** runs on a standalone EC2 box, reached via a ClusterIP + manual endpoint) | none |
| `superset` | Superset staging tenants (`demosuperset`, `t4dsuperset`) | **public nginx** ingress + cert-manager LetsEncrypt |
| `monitoring` | kube-prometheus-stack (Grafana, Prometheus, Alertmanager) — persistent (gp3) | Grafana via the shared **nginx NLB** at `grafana-staging.dalgo.org` |
| `ingress-nginx` / `cert-manager` | nginx controller + LetsEncrypt issuer | — |

## Ingress / load balancers
- Two IngressClasses: **`alb`** (AWS LB Controller — used `internal` for Airbyte) and **`nginx`** (ingress-nginx — public, for Superset **and Grafana**).
- LBs: Airbyte internal ALB · nginx internet-facing NLB (`dalgo-staging-nginx-elb`) — fronts **Superset + Grafana**.

## Node groups
`static-control`, `dynamic` (jobs), `prefect-worker`, and `supersets` (dedicated, tainted `dedicated=superset:NoSchedule` / label `workload=superset`).

## Folder structure
```
airbyte/      Airbyte cluster (eksctl tf) + helm values
prefect/      prefect-worker helm values + metrics-server
superset/     per-tenant Superset values (demosuperset, t4dsuperset) + helm helpers
cluster/      ingress-nginx + cert-manager (letsencrypt) setup for this cluster
monitoring/   kube-prometheus-stack (grafana) values + PV/PVCs
```
