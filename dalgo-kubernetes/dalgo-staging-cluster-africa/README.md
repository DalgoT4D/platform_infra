# dalgo-staging-cluster-africa (TEST)

Africa (`af-south-1`) part of Dalgo staging, for orgs that need data residency. Copied from
`../dalgo-staging-cluster` and edited. Same AWS account, same profile (`dalgo-staging-admin`).

Only Airbyte (+ its own RDS and S3 bucket) and the Prefect **workers** run here. The Prefect server,
Django + Celery (`dalgo-staging-ec2`), the Dalgo DB, Superset and monitoring stay in Mumbai (`ap-south-1`).
The two VPCs are linked by inter-region VPC peering.

```
Mumbai VPC 172.31.0.0/16                         Africa VPC 10.20.0.0/16
 staging EC2 (Django/Celery) --HTTP:80----------> internal ALB (only the EC2 /32) -> Airbyte server
 staging EC2 (Prefect :4200) <------------------- Prefect worker + flow-run pods
                        inter-region VPC peering   flow pods -> Airbyte svc :8001 (in-cluster)
                                                   NAT EIP -> sources, warehouses, GitHub, Docker Hub
                                                   RDS (Airbyte), S3 bucket (gateway endpoint), ECR cache
```

## Folders

```
bootstrap/          terraform: VPC 10.20.0.0/16, subnets, IGW, NAT, route tables, S3 endpoint, ECR cache, RDS SG
staging-rds/        terraform: Airbyte's own Postgres (single AZ, private)
cluster/terraform/  terraform: EKS dalgo-staging-af-cluster, node groups, add-ons, IAM + Pod Identity
cluster/ingress/    AWS Load Balancer Controller install (helm)
cluster/autoscaler/ cluster-autoscaler install (helm)
peering/            terraform: Mumbai <-> Africa peering, routes both sides, SG rules (4200 / 5432 / 22), private zone link
airbyte/helm/       Airbyte values (full copy), secret example, internal ALB ingress
prefect/prefect-workers/  worker values, EndpointSlice example; reuses Mumbai's Service + base job template
```

Not copied: `staging-ec2/`, `monitoring/`, `superset/` (Mumbai only). LB controller / autoscaler:
`cluster/ingress/`, `cluster/autoscaler/` (copies of Mumbai's docs with Africa values).

## Terraform state

Same bucket as Mumbai (`terraform-state-and-lock-bucket`, in `ap-south-1`), **different keys**:

| Folder | Key |
|---|---|
| `bootstrap/` | `dalgo-staging-af/bootstrap/terraform.tfstate` |
| `staging-rds/` | `dalgo-staging-af/staging-rds/terraform.tfstate` |
| `cluster/terraform/` | `dalgo-staging-af/eks/terraform.tfstate` |
| `peering/` | `dalgo-staging-af/peering/terraform.tfstate` |

`peering/` also **reads** (never writes) Mumbai's `dalgo-staging/bootstrap/...` and `dalgo-staging/staging-ec2/...`.
Every `backend "s3"` has `region = "ap-south-1"`: that is where the bucket is, not where the resources go.

## Kube context: read this first

The Africa cluster uses the same namespace names as Mumbai (`airbyte-staging`, `prefect-staging`) and the same
release names. A `helm upgrade` or `kubectl apply` against the wrong context changes **Mumbai**. So:

- add the cluster with `--alias dalgo-staging-af` (below),
- every command here passes `--context dalgo-staging-af` / `--kube-context dalgo-staging-af`,
- don't `kubectl config use-context` to Africa and forget about it.

## Manual AWS steps (outside Terraform)

Before anything:

1. **Enable the opt-in region** (af-south-1 is opt-in):
   `aws account get-region-opt-status --region-name af-south-1 --profile dalgo-staging-admin`;
   if not `ENABLED`: `aws account enable-region --region-name af-south-1 --profile dalgo-staging-admin` and wait.
2. **STS v2 tokens** (global-endpoint v1 tokens are not valid in opt-in regions; harmless if already set):
   `aws iam set-security-token-service-preferences --global-endpoint-token-version v2Token --profile dalgo-staging-admin`
3. **Check af-south-1 offers** t4g.large/t4g.medium in af-south-1a, EKS 1.36, the AMI release and add-on versions
   in `cluster/terraform/variables.tf`, Postgres 18 + db.t3.small; and the vCPU (L-1216C47A) / EIP quotas.
4. **Docker Hub creds for the ECR pull-through cache**: the secret must exist in af-south-1 with the same name.
   `aws secretsmanager replicate-secret-to-regions --secret-id ecr-pullthroughcache/docker-hub --add-replica-regions Region=af-south-1 --region ap-south-1 --profile dalgo-staging-admin`
   (bootstrap fails on the data source lookup until this exists).
5. **Airbyte S3 bucket** (made by hand, as in Mumbai): `dalgo-staging-af-airbyte` in af-south-1, block all public access, default SSE-S3.
   `aws s3api create-bucket --bucket dalgo-staging-af-airbyte --region af-south-1 --create-bucket-configuration LocationConstraint=af-south-1 --profile dalgo-staging-admin`
   If the name is taken, change it in `cluster/terraform/cluster.tf` (`app_s3_pod_roles`), `airbyte/helm/values1.8.3.yaml` and the k8s secret.
6. **EKS node key pair** (af-south-1): EC2 -> Key pairs -> Create `dalgo-staging-af-eks-rsa-key-pair` (RSA, .pem). Keep the .pem on the Mumbai staging EC2 / vault. SSH into nodes only from that EC2, over peering: `ssh -i <key>.pem ec2-user@<africa node private IP>` (rule in `peering/`).

Later, at the steps noted below: Mumbai bootstrap apply, Airbyte DB user, k8s secrets, Prefect work pool,
backend region secret, Mumbai EC2 firewall.

## Apply order

In every terraform folder: `cp terraform.tfvars.example terraform.tfvars` (fill `aws_account_id`, etc.),
`terraform init`, `terraform plan -out tfplan`, **read the plan**, `terraform apply tfplan`.

### 0. Mumbai bootstrap (one time, needed by peering)

`../dalgo-staging-cluster/bootstrap` changes: the inline `route {}` blocks on both route tables become separate
`aws_route` resources (adopted with two `import` blocks), so peering routes added from `peering/` survive bootstrap
applies; plus the `public_route_table_id` / `private_route_table_id` outputs. Plan there must show
**`2 to import, 0 to add, 0 to change, 0 to destroy`** and the new outputs. Anything else (especially a destroy or
a route table replacement): stop. Apply it. The two `import` blocks can be deleted afterwards.

### 1. `bootstrap/`

Outputs worth noting: `nat_public_ip` (clients whitelist this for Africa syncs/dbt), `ecr_docker_hub_registry`
(must equal `global.image.registry` in the Airbyte values).

### 2. `staging-rds/`

Set `master_password` (new, vault) in tfvars. `terraform output endpoint` = `<AFRICA_RDS_ENDPOINT>`.

### 3. `cluster/terraform/` (~15-20 min)

Then: `terraform output acm_validation_records` -> if that CNAME isn't already in Cloudflare (from Mumbai's
`*.dalgo.org` cert), add it (DNS only). Wait until the cert is ISSUED (ACM console, af-south-1) before the Airbyte ingress.

```bash
terraform -chdir=cluster/terraform output kubeconfig_command
aws eks update-kubeconfig --name dalgo-staging-af-cluster --region af-south-1 --profile dalgo-staging-admin --alias dalgo-staging-af
kubectl --context dalgo-staging-af get nodes -L type
```

Cluster add-ons (same charts/versions as Mumbai, Africa values). Install both before Airbyte:

1. `cluster/ingress/aws-load-balancer-controller.md`
2. `cluster/autoscaler/cluster-autoscaler.md`

### 4. `peering/`

Expect: 1 peering connection + 1 accepter, 2 + 2 routes, SG rules (Mumbai EC2: 4200 from 10.20.0.0/16; Africa RDS:
5432 and Africa cluster SG: 22, both from the Mumbai EC2 /32), and the Mumbai VPC association of the Africa
Airbyte private zone. Apply after `cluster/terraform` (reads its state).
`terraform output -raw mumbai_ec2_private_ip` = `<MUMBAI_EC2_PRIVATE_IP>`.

On the Mumbai EC2: if `sudo ufw status` is active, `sudo ufw allow from 10.20.0.0/16 to any port 4200 proto tcp`.

### 5. Airbyte: `airbyte/helm/README.md`

DB user via in-cluster psql, k8s secret, helm install, internal ALB ingress, check from the Mumbai EC2.

### 6. Prefect workers: `prefect/prefect-workers/README.md`

Work pool `staging_af_eks_dalgo_work_pool` on the Mumbai Prefect server first, then Service/EndpointSlice, then the worker.

### 7. Backend region secret (Mumbai Secrets Manager)

`dalgoAirbyteRegion-staging-af` in **ap-south-1** (the staging EC2 role can already read `dalgoAirbyteRegion-staging-*`,
`../dalgo-staging-cluster/staging-ec2/main.tf`). Airbyte connection creds only; the backend and the
Prefect AirbyteServer block both use this host (Africa flow pods must reach it too):

```json
{"server_host": "airbyte-staging-af-internal.dalgo.org", "server_port": "443", "api_version": "v1", "use_ssl": true, "api_token": ""}
```

`api_token` is empty (Airbyte auth off). Non-secret config goes in the backend `.env`:
`PREFECT_AF_WORKER_POOL_NAME=staging_af_eks_dalgo_work_pool` (and optionally `AIRBYTE_AF_URL_FOR_NOTIFICATIONS`).
Check with `python manage.py check_region_secrets`.

```bash
aws secretsmanager create-secret --name dalgoAirbyteRegion-staging-af --region ap-south-1 \
  --profile dalgo-staging-admin --secret-string file://airbyte-af.json   # delete the file afterwards
```

## Placeholders

| Placeholder | Where | Value from |
|---|---|---|
| `aws_account_id`, `master_password` | `*/terraform.tfvars` (gitignored) | account id; new password (vault) |
| `admin_principal_arns` | `cluster/terraform/terraform.tfvars` | SSO PowerUser role ARN (or `[]`) |
| `<AFRICA_RDS_ENDPOINT>` | `airbyte/helm/values1.8.3.yaml` (2x), Airbyte secret `database-host` | `terraform output endpoint` in `staging-rds/` |
| `<AFRICA_AIRBYTE_DB_PASSWORD>` | Airbyte secret + psql | generate: `openssl rand -base64 24 \| tr -d '/@"+='` |
| `<SAME gcp.json AS MUMBAI>` | Airbyte secret `gcp.json` | Mumbai `airbyte-config-secrets` |
| `<MUMBAI_EC2_PRIVATE_IP>` | `airbyte/helm/airbyte-internal-ingress.yaml`, Prefect EndpointSlice | `terraform output mumbai_ec2_private_ip` in `peering/` |
| `<AFRICA_ACM_CERT_ARN>` | `airbyte/helm/airbyte-internal-ingress.yaml` | `terraform output -raw acm_certificate_arn` in `cluster/terraform/` |

If the Mumbai EC2 is **replaced** (new private IP): re-apply the Africa EndpointSlice and the Africa Ingress
(and Mumbai's own EndpointSlice).

## Teardown (reverse order)

1. `kubectl --context dalgo-staging-af delete -f airbyte/helm/airbyte-internal-ingress.yaml`; wait until the ALB is gone.
2. `helm --kube-context dalgo-staging-af uninstall` airbyte (`airbyte-staging`), prefect-worker (`prefect-staging`),
   then aws-load-balancer-controller and cluster-autoscaler (`kube-system`).
3. On the Mumbai EC2: `prefect work-pool delete staging_af_eks_dalgo_work_pool`. Delete secret `dalgoAirbyteRegion-staging-af`.
4. `terraform destroy` in `peering/` (removes only the link: peering, 4 routes, the 4200 rule).
5. `terraform destroy` in `cluster/terraform/`.
6. `staging-rds/`: set `deletion_protection = false` in `main.tf`, apply, then destroy (a final snapshot is taken).
7. Empty + delete the `dalgo-staging-af-airbyte` bucket. `terraform destroy` in `bootstrap/`.
