# dalgo-staging-cluster (new account)

Staging EKS cluster in Dalgo NonProd (323443472031), ap-south-1, VPC `dalgo-staging` / `vpc-05c8d0fed51fca8f4`.
Hosts the full staging data platform: Airbyte, Prefect, Superset, and monitoring.
Replaces `../dalgo-staging-cluster` (old account 024209611402).

## What runs here

| Namespace | What | Exposure |
|-----------|------|----------|
| `airbyte` | Airbyte ingestion stack | **internal ALB** (`airbyte-internal-ingress`, group `dalgo-staging-internal`) |
| `prefect` | in-cluster `prefect-worker` (Prefect **server** runs on a standalone EC2 box, reached via a ClusterIP + manual endpoint) | none |
| `superset` | Superset staging tenant `demosuperset` | **internet-facing ALB** (group `dalgo-staging-public`) |
| `monitoring` | kube-prometheus-stack (Grafana, Prometheus, Alertmanager), persistent on gp3 | Grafana on the same internet-facing ALB at `grafana-staging.dalgo.org` |

## Ingress / load balancers
- One IngressClass: **`alb`** (AWS Load Balancer Controller). ingress-nginx, the NLB and cert-manager are gone.
- Two ALBs: internal (Airbyte) and internet-facing (Superset + Grafana). TLS uses the ACM cert `*.dalgo.org` from terraform.

## Node groups
`static-control`, `dynamic` (jobs), `prefect-worker`, and `supersets` (dedicated, tainted `dedicated=superset:NoSchedule` / label `workload=superset`). All in private subnet 1b.

## Folder structure
```
cluster/terraform/   EKS cluster, node groups, add-ons, IAM + Pod Identity roles, ACM cert, private DNS zone
cluster/ingress/     AWS Load Balancer Controller install (helm)
cluster/autoscaler/  cluster-autoscaler install (helm)
airbyte/helm/        Airbyte values 1.8.3, secrets example, internal ALB ingress
prefect/             prefect-worker values + external Prefect server service/endpoint
superset/            demosuperset values + env example
monitoring/          kube-prometheus-stack values, gp3 StorageClass, grafana secret example
```

## Order to bring it up
1. `cluster/terraform`: `terraform apply`. Add the ACM validation CNAME in Cloudflare.
2. `cluster/ingress`: install the AWS Load Balancer Controller.
3. `cluster/autoscaler`: install cluster-autoscaler.
4. `monitoring`: gp3 StorageClass, then kube-prometheus-stack.
5. `airbyte`, `prefect`, `superset`: each folder's README.
6. DNS: Cloudflare CNAMEs → public ALB; private zone alias → internal ALB.

## Secrets
Each `*.example.yaml` has a filled-in twin (`airbyte-config-secrets.yaml`, `prefect-external-service-endpoint.yaml`, `superset-env.yaml`, `grafana-admin-secret.yaml`). Those, `terraform.tfvars`, state and plan files are gitignored: never commit them.

## Account-specific values
The RDS endpoint, S3 bucket and ACM certificate ARN are already set for this account. `# MIGRATION` comments record the old-account value they replaced. If the cluster is rebuilt, take the new ARN from `terraform output acm_certificate_arn` and update it in `airbyte/helm/airbyte-internal-ingress.yaml`, `superset/demosuperset/values6.0.0.yaml` and `monitoring/values.yaml`.
