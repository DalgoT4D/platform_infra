# dalgo-superset-production-cluster

Dedicated **production Superset** EKS cluster (ap-south-1, VPC `dalgo-prod-vpc` / `vpc-060665f96234a5997`).
Runs all production client/NGO Superset instances, isolated from the main prod data platform.

> Based on repo structure + known setup; a live peek wasn't available this run — verify against the cluster.

## What runs here
- **~20 per-tenant Superset deployments** — each its own Helm release + namespace
  (`1000DaysFund`, `akrsp`, `atecf`, `bhumi`, `cmhlp`, `dalgo_internal`, `dani-sports-foundation`,
  `goonj`, `inrem`, `janaagraha`, `mad`, `moonshine`, `noora_health`, `peepul`, `search`, `sneha`,
  `stir_education`, `ummeed`, …).
- Shared **nginx ingress controller + cert-manager (LetsEncrypt)** — TLS per tenant host.
- Superset **metadata DBs are external (RDS)**; per-tenant in-cluster redis for cache/celery.
- Own monitoring stack.

## Ingress / load balancers
- `nginx` IngressClass; a public internet-facing **nginx ELB** fronts all tenant hostnames (host-based routing).

## Folder structure
```
superset/     per-tenant Superset helm values (1000DaysFund … ummeed) + metrics-server
cluster/      ingress-nginx + letsencrypt + cluster tf
monitoring/   superset cluster monitoring
```
