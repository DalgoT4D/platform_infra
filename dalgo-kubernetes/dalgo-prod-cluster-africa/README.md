# dalgo-prod-cluster-africa

Africa (`af-south-1`) part of Dalgo **production**, for orgs that need data residency. Copy of
`../dalgo-staging-cluster-africa` with prod values. Prod account `024209611402`, profile `dalgo-prod-admin`
(SSO AdministratorAccess; set up with `aws configure sso`).

Only Airbyte (+ its own RDS and S3 bucket) and the Prefect **workers** run here. The Prefect server, Django + Celery
(`dalgo-production-arm`), the Dalgo DB, Superset and monitoring stay in Mumbai prod (`ap-south-1`).

```
Mumbai prod VPC 172.31.0.0/16 (NOT terraform)      Africa prod VPC 10.30.0.0/16 (terraform, this folder)
 dalgo-production-arm 172.31.2.21
   Django/Celery --HTTPS-----------------------------> internal ALB (only the EC2 /32 + 10.30/16) -> Airbyte
   Prefect :4200 <---------------------------------- Prefect worker + flow-run pods
                         inter-region VPC peering      flow pods -> Airbyte (internal ALB host)
                                                       NAT EIP -> sources, warehouses, GitHub, Docker Hub
                                                       RDS (Airbyte), S3 bucket (gateway endpoint), ECR cache
```

**Mumbai prod is hand-built and is never touched by terraform from here.** Every Mumbai change is a manual step
below. `peering/` has no ap-south-1 provider at all.

## Folders

```
bootstrap/          terraform: VPC 10.30.0.0/16, subnets, IGW, NAT, route tables, S3 endpoint, ECR cache, RDS SG
prod-rds/           terraform: Airbyte's own Postgres (single AZ, private, deletion protection)
cluster/terraform/  terraform: EKS dalgo-prod-af-cluster, node groups, add-ons, IAM + Pod Identity, ACM cert, private zone
cluster/ingress/    AWS Load Balancer Controller install (helm)
cluster/autoscaler/ cluster-autoscaler install (helm)
peering/            terraform: peering REQUEST from Africa, Africa routes, Africa SG rules (5432 / 22 from the Mumbai EC2)
airbyte/helm/       Airbyte values (full copy), secret example, internal ALB ingress
prefect/prefect-workers/  worker values, base job template, Service + EndpointSlice
```

## Terraform state

Prod bucket `production-eks-terraform-state` (ap-south-1), new keys only. `global/terraform.tfstate` in that bucket
is the old eksctl state of the Mumbai prod cluster: never point anything at it.

| Folder | Key |
|---|---|
| `bootstrap/` | `dalgo-prod-af/bootstrap/terraform.tfstate` |
| `prod-rds/` | `dalgo-prod-af/prod-rds/terraform.tfstate` |
| `cluster/terraform/` | `dalgo-prod-af/eks/terraform.tfstate` |
| `peering/` | `dalgo-prod-af/peering/terraform.tfstate` |

`backend "s3"` has `region = "ap-south-1"`: where the bucket is, not where the resources go.

## Kube context: read this first

Same namespace and release names as Mumbai prod (`airbyte`, `prefect`, `kube-system` add-ons). A `helm upgrade` or
`kubectl apply` against the wrong context changes **Mumbai prod**. So:

- add the cluster with `--alias dalgo-prod-af` (below),
- every command passes `--context dalgo-prod-af` / `--kube-context dalgo-prod-af`,
- never `kubectl config use-context` to Africa and forget about it.

## Manual AWS steps, before anything

1. **Profile:** `aws configure sso` -> account 024209611402, AdministratorAccess, name it `dalgo-prod-admin`.
   `aws sts get-caller-identity --profile dalgo-prod-admin` must show 024209611402.
2. **State bucket versioning** (recover a broken state):
   `aws s3api put-bucket-versioning --bucket production-eks-terraform-state --versioning-configuration Status=Enabled --profile dalgo-prod-admin`
3. **Enable the opt-in region** (currently DISABLED in prod):
   `aws account enable-region --region-name af-south-1 --profile dalgo-prod-admin`, then wait until
   `aws account get-region-opt-status --region-name af-south-1 --profile dalgo-prod-admin` says `ENABLED`.
   If the new organization has an SCP that denies af-south-1, ask the org admin first.
4. **STS v2 tokens** (v1 global-endpoint tokens are not valid in opt-in regions):
   `aws iam set-security-token-service-preferences --global-endpoint-token-version v2Token --profile dalgo-prod-admin`
5. **vCPU quota** (new regions start low, ~10 vCPU = 5 t4g nodes): request L-1216C47A = 32 in af-south-1.
   `aws service-quotas request-service-quota-increase --service-code ec2 --quota-code L-1216C47A --desired-value 32 --region af-south-1 --profile dalgo-prod-admin`
6. **Check af-south-1 offers** t4g.large / t4g.medium in af-south-1a, EKS 1.36, the AMI release and add-on versions in
   `cluster/terraform/variables.tf`, Postgres 18 + db.t3.small.
7. **Docker Hub creds for the ECR cache** (secret must exist in af-south-1, same name):
   `aws secretsmanager replicate-secret-to-regions --secret-id ecr-pullthroughcache/docker-hub --add-replica-regions Region=af-south-1 --region ap-south-1 --profile dalgo-prod-admin`
8. **Airbyte S3 bucket** `dalgo-prod-af-airbyte` (block all public access, default SSE-S3):
   `aws s3api create-bucket --bucket dalgo-prod-af-airbyte --region af-south-1 --create-bucket-configuration LocationConstraint=af-south-1 --profile dalgo-prod-admin`
   If the name is taken, change it in `cluster/terraform/cluster.tf` (`app_s3_pod_roles`), `airbyte/helm/values1.8.3.yaml` and the k8s secret.
9. **EKS node key pair** in af-south-1: EC2 -> Key pairs -> `dalgo-prod-af-eks-rsa-key-pair` (RSA, .pem). Keep the .pem in the vault.
   SSH into nodes only from `dalgo-production-arm`, over peering.

## Apply order

In every terraform folder: `cp terraform.tfvars.example terraform.tfvars`, fill it, `terraform init`,
`terraform plan -out tfplan`, **read the plan**, `terraform apply tfplan`.

### 1. `bootstrap/`

Outputs: `nat_public_ip` (clients whitelist this for Africa syncs/dbt), `ecr_docker_hub_registry` (must equal
`global.image.registry` in the Airbyte values).

### 2. `prod-rds/`

Set `master_password` (new, vault) in tfvars. `terraform output -raw endpoint` = `<AFRICA_RDS_ENDPOINT>`.

### 3. `cluster/terraform/` (~15-20 min)

`terraform output acm_validation_records`: if that CNAME isn't in Cloudflare already (Mumbai prod's `*.dalgo.org` cert
is in the same account, so usually it is), add it (DNS only). Wait until the cert is ISSUED (ACM, af-south-1).

```bash
aws eks update-kubeconfig --name dalgo-prod-af-cluster --region af-south-1 --profile dalgo-prod-admin --alias dalgo-prod-af
kubectl --context dalgo-prod-af get nodes -L type
```

Then the add-ons, both before Airbyte:

1. `cluster/ingress/aws-load-balancer-controller.md`
2. `cluster/autoscaler/cluster-autoscaler.md`

One LB controller serves internal and internet-facing ALBs (per Ingress, `scheme` annotation). Today only the
internal Airbyte ALB exists; nothing in Africa prod is public.

### 4. `peering/` (two applies + Mumbai manual steps)

1. `peering_accepted = false`, apply. Creates the peering request, RDS 5432 and node SSH 22 rules (from 172.31.2.21/32).
2. `terraform output -raw mumbai_manual_steps`: run those commands yourself, one by one (they are also below).
3. `peering_accepted = true`, apply. Adds the Africa -> Mumbai routes.

### 5. Mumbai prod manual steps (by hand)

Values were read from the account on 2026-11-21. Re-check them before running: if anything moved, stop.

| # | What | Where | Value |
|---|---|---|---|
| 1 | Accept the peering | VPC -> Peering connections (ap-south-1) | `pcx-…` from `terraform output peering_connection_id` |
| 2 | Route Mumbai -> Africa | Route table `rtb-0b63cbb452c6bc882` (VPC main table; `dalgo-production-arm`'s subnet `subnet-0181641712cc0826a` uses it) | `10.30.0.0/16 -> pcx-…` |
| 3 | Prefect from Africa | SG `sg-04d35add536d7604d` (`ddp-production-server`) | inbound TCP 4200 from `10.30.0.0/16` |
| 4 | Backend resolves the Africa Airbyte name | Route 53 private zone `airbyte-prod-af-internal.dalgo.org` | associate VPC `vpc-060665f96234a5997` (ap-south-1) |
| 5 | Host firewall | on `dalgo-production-arm` | if `sudo ufw status` is active: `sudo ufw allow from 10.30.0.0/16 to any port 4200 proto tcp` |
| 6 | Backend can read the region secret | IAM role `app-dalgo-prod-ec2-role`, inline policy with the secretsmanager actions | add `arn:aws:secretsmanager:ap-south-1:024209611402:secret:dalgoAirbyteRegion-prod-*` to its Resource list (GetSecretValue/DescribeSecret) |

Step 2 is on the main table: every subnet without its own table gets the route. Harmless (only 10.30/16 traffic
goes to the peering), and the table's other routes are untouched. The main table also has a blackholed
`10.0.0.0/16 -> pcx-09e65e3dc2618137f` (old peering): unrelated, leave it.

Check from `dalgo-production-arm` after step 4 of the Airbyte README: `curl -s https://airbyte-prod-af-internal.dalgo.org/api/v1/health`.

### 6. Airbyte: `airbyte/helm/README.md`

DB user via in-cluster psql, k8s secret, helm install, internal ALB ingress + alias record, check from the Mumbai EC2.

### 7. Prefect workers: `prefect/prefect-workers/README.md`

Work pool `prod_af_eks_dalgo_work_pool` on the Mumbai Prefect server first, then Service/EndpointSlice, then the worker.

### 8. Backend region secret (Mumbai Secrets Manager)

`dalgoAirbyteRegion-prod-af` in **ap-south-1** (needs manual step 6). Airbyte connection only; the backend and the
Prefect AirbyteServer block both use this host:

```json
{"server_host": "airbyte-prod-af-internal.dalgo.org", "server_port": "443", "api_version": "v1", "use_ssl": true, "api_token": ""}
```

```bash
aws secretsmanager create-secret --name dalgoAirbyteRegion-prod-af --region ap-south-1 \
  --profile dalgo-prod-admin --secret-string file://airbyte-af.json   # delete the file afterwards
```

Backend `.env`: `PREFECT_AF_WORKER_POOL_NAME=prod_af_eks_dalgo_work_pool` (optionally `AIRBYTE_AF_URL_FOR_NOTIFICATIONS`).
Check with `python manage.py check_region_secrets`.

## Placeholders

| Placeholder | Where | Value from |
|---|---|---|
| `master_password` | `prod-rds/terraform.tfvars` (gitignored) | new password (vault) |
| `admin_principal_arns` | `cluster/terraform/terraform.tfvars` | SSO PowerUser role ARN (`AWSReservedSSO_PowerUserAccess_…`) or `[]` |
| `<AFRICA_RDS_ENDPOINT>` | `airbyte/helm/values1.8.3.yaml` (2x), Airbyte secret `database-host` | `terraform output -raw endpoint` in `prod-rds/` |
| `<AFRICA_AIRBYTE_DB_PASSWORD>` | Airbyte secret + psql | `openssl rand -base64 24 \| tr -d '/@"+='` |
| `<AFRICA_ACM_CERT_ARN>` | `airbyte/helm/airbyte-internal-ingress.yaml` | `terraform output -raw acm_certificate_arn` in `cluster/terraform/` |

The Mumbai EC2 IP `172.31.2.21` is already filled in (Ingress `inbound-cidrs`, EndpointSlice, `peering/` default).
If `dalgo-production-arm` is **replaced** (new private IP): update those three and re-apply them.

## Teardown (reverse order)

1. `kubectl --context dalgo-prod-af delete -f airbyte/helm/airbyte-internal-ingress.yaml`; wait until the ALB is gone.
2. `helm --kube-context dalgo-prod-af uninstall` airbyte (`airbyte`), prefect-worker (`prefect`),
   then aws-load-balancer-controller and cluster-autoscaler (`kube-system`).
3. On `dalgo-production-arm`: `prefect work-pool delete prod_af_eks_dalgo_work_pool`. Delete secret `dalgoAirbyteRegion-prod-af`.
4. **Mumbai, by hand** (reverse of the manual steps):
   - `aws ec2 delete-route --route-table-id rtb-0b63cbb452c6bc882 --destination-cidr-block 10.30.0.0/16 --region ap-south-1 --profile dalgo-prod-admin`
   - remove the 4200-from-10.30.0.0/16 rule on `sg-04d35add536d7604d` (and the ufw rule, if added)
   - `aws route53 disassociate-vpc-from-hosted-zone --hosted-zone-id <zone id> --vpc VPCRegion=ap-south-1,VPCId=vpc-060665f96234a5997 --profile dalgo-prod-admin`
   - remove `dalgoAirbyteRegion-prod-*` from `app-dalgo-prod-ec2-role`
5. `terraform destroy` in `peering/` (deletes the peering connection, Africa routes, Africa SG rules).
6. `terraform destroy` in `cluster/terraform/`.
7. `prod-rds/`: set `deletion_protection = false` in `main.tf`, apply, then destroy (a final snapshot is taken).
8. Empty + delete the `dalgo-prod-af-airbyte` bucket. `terraform destroy` in `bootstrap/`.
