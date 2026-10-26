# dalgo-staging-cluster

Staging for Dalgo in the Dalgo NonProd AWS account, `ap-south-1`.
Everything is built from this folder: network, staging EC2, RDS, EKS cluster and the apps on it.
AWS profile for every command: `dalgo-staging-admin` (`aws sso login --profile dalgo-staging-admin`).

## What runs where

| Where | What | Exposure |
|---|---|---|
| EC2 `dalgo-staging-ec2` | Django backend, webapp, ai-llm, prefect-proxy, Prefect **server** (nginx in front) | public IP, 443 from Cloudflare only |
| RDS `dalgo-staging-rds` | Postgres 18: `dalgo`, `airbyte` (+ temporal), `prefect` databases | private, 5432 from EC2 + EKS |
| EKS ns `airbyte-staging` | Airbyte 1.8.3 | **internal ALB** → `airbyte-staging-internal.dalgo.org` (Route53 private zone) |
| EKS ns `prefect-staging` | `prefect-worker` + flow-run pods (talks to the Prefect server on the EC2) | none |
| EKS ns `superset-staging` | Superset `demosuperset` | **public ALB** → `demosuperset.dalgo.org` (Cloudflare) |
| EKS ns `monitoring-staging` | kube-prometheus-stack (Grafana, Prometheus, Alertmanager) on gp3 disks | same public ALB → `grafana-staging.dalgo.org` (Cloudflare) |
| EKS ns `kube-system` | AWS Load Balancer Controller, cluster-autoscaler, EKS add-ons | none |

## Network layout

- VPC `dalgo-staging-vpc` (`172.31.0.0/16`), one public + one private subnet in each of 1a, 1b, 1c.
- **Data path is in `ap-south-1a` only**: EC2, RDS, EKS nodes and the NAT gateway. No cross-AZ traffic.
- `ap-south-1b` only adds availability for the EKS control plane and the ALBs (both need 2 AZs).
  Only 1a and 1b subnets carry the `kubernetes.io/role/(internal-)elb` tags, so ALBs never use 1c.
- `ap-south-1c` is spare (part of the RDS subnet group).
- Outbound IP of everything private (EKS pods): the NAT EIP, `terraform output nat_public_ip` in `bootstrap/`.
  Clients that whitelist Dalgo staging need this IP.

## Folder structure

```
bootstrap/            terraform: VPC, subnets, IGW, NAT, route tables, security groups (EC2, RDS, Cloudflare 443)
staging-rds/          terraform: RDS + subnet group + parameter group; optional restore from a snapshot (README inside)
staging-ec2/          terraform: the staging EC2 (Ubuntu arm64); software on it is set up by hand
cluster/terraform/    terraform: EKS cluster, node groups, add-ons, IAM + Pod Identity roles, ACM cert, private zone
cluster/ingress/      AWS Load Balancer Controller install (helm)
cluster/autoscaler/   cluster-autoscaler install (helm)
airbyte/helm/         Airbyte values, secrets example, internal ALB ingress
prefect/              prefect-worker values, base job template, external Prefect server service/endpoint
superset/             demosuperset values + env example
monitoring/           kube-prometheus-stack values, gp3 StorageClass, grafana secret example
```

Terraform state: S3 bucket `terraform-state-and-lock-bucket`, key `dalgo-staging/<stack>/terraform.tfstate`
(`bootstrap`, `staging-rds`, `staging-ec2`, `eks`). `staging-rds`, `staging-ec2` and `cluster/terraform`
read VPC, subnet and SG IDs from the bootstrap state, so bootstrap goes first.

## Order to bring it up

In every terraform folder: `terraform init`, `terraform plan -out tfplan`, read the plan, `terraform apply tfplan`.

1. `bootstrap/`
2. `staging-rds/`: set `snapshot_identifier` in tfvars to restore, leave it unset for an empty DB.
   Name clash on a rebuild: delete the old `dalgo-staging-rds-pg-18-param-group` first.
3. `staging-ec2/`: key pair `dalgo-staging-ec2-rsa-key-pair` must exist. Then by hand: nginx, `ddp` user, docker, swap,
   `.env` files, client dbt repos, dev secrets.
4. `cluster/terraform/`: key pair `dalgo-staging-eks-rsa-key-pair` must exist.
   - `terraform output acm_validation_records` → CNAME in Cloudflare (DNS only). Already there if the domain was validated before.
   - `terraform output acm_certificate_arn` → put it in `airbyte/helm/airbyte-internal-ingress.yaml`,
     `superset/demosuperset/values6.0.0.yaml`, `monitoring/values.yaml`.
   - `aws eks update-kubeconfig --name dalgo-staging-cluster --region ap-south-1 --profile dalgo-staging-admin --alias dalgo-staging`
5. `cluster/autoscaler/`, then `cluster/ingress/` (helm).
6. Apps, each from its README (namespace and secret first): `prefect/`, `airbyte/`, `superset/`, `monitoring/`.
   - Prefect: endpoint file needs the EC2 private IP. After a DB restore, push the work pool template again:
     `prefect work-pool update staging_eks_dalgo_work_pool --base-job-template base_job_template.json`
     (the helm value only applies when the pool is first created).
7. DNS:
   - Route53 private zone `airbyte-staging-internal.dalgo.org`: alias A record (apex) → internal ALB.
   - Cloudflare: CNAME `demosuperset` and `grafana-staging` → public ALB (`kubectl get ingress -A`).
   - Cloudflare: staging app/API A records → EC2 public IP (`terraform output public_ip` in `staging-ec2/`).

## Node groups

All nodes run in private subnet 1a. The autoscaler scales each group between min and max.

| Node group | Label | Taint | Runs |
|---|---|---|---|
| `static-control` | `type=static` | none | Airbyte core, plus every pod without a nodeSelector (kube-system, monitoring) |
| `dynamic` | `type=jobs` | none | Airbyte sync jobs |
| `prefect-worker` | `type=prefect-worker` | none | Prefect worker and flow runs |
| `supersets` | `type=superset` | `dedicated=superset:NoSchedule` | Superset only |

Label + nodeSelector pins a pod to its group (it stays Pending rather than land elsewhere).
The taint keeps every other pod off the Superset nodes; Superset carries the matching toleration.

## Tags and names

Every resource has `Name`, `Product=dalgo`, `Environment=staging`, `Subset`, `ManagedBy`.
`Subset` is `airbyte` / `prefect` / `superset` / `monitoring` for single-app resources, `shared` otherwise
(network, EC2, RDS, cluster, IAM, the shared public ALB). Names start with `dalgo-staging-`.

- Node EC2s get their tags from the node group ASG at launch: nodes that existed before the tags were added need
  `aws ec2 create-tags` once. Node root volumes stay untagged (no custom launch template).
- ALBs get tags from the `alb.ingress.kubernetes.io/tags` annotation. Superset and Grafana share one ALB:
  keep that annotation identical on both, or the controller refuses the group.
- Monitoring EBS volumes get tags from the gp3 StorageClass.

## Secrets

Filled-in secret files are gitignored (see `../.gitignore`): copy the `.example` file, fill it, never commit it.
`airbyte-config-secrets.yaml`, `superset-env.yaml` (keep `SUPERSET_SECRET_KEY` stable, it encrypts saved DB
connections), `grafana-admin-secret.yaml`, `prefect-external-service-endpoint.yaml`, all `terraform.tfvars`.

## Tearing it down

1. Delete the Airbyte ingress (`kubectl delete -f airbyte/helm/airbyte-internal-ingress.yaml`, not helm-managed),
   then `helm uninstall` airbyte, prefect-worker, demosuperset, kube-prometheus-stack.
2. Wait until `kubectl get ingress -A` is empty and the ALBs are gone from the console.
   Removing the LB controller earlier leaves the ALBs behind and blocks VPC deletion.
3. `helm uninstall` aws-load-balancer-controller and cluster-autoscaler (kube-system).
4. `terraform destroy` in `cluster/terraform`, then delete the leftover monitoring EBS volumes (`reclaimPolicy: Retain`).
5. RDS: manual snapshot first, then `terraform destroy` in `staging-rds` (turn `deletion_protection` off first).
6. `terraform destroy` in `staging-ec2`, then `bootstrap`.
