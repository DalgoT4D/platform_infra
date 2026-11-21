# AWS Load Balancer Controller (ALB ingress) - Africa

Copy of `../../../dalgo-staging-cluster-africa/cluster/ingress/aws-load-balancer-controller.md` with prod Africa values.
The controller watches `Ingress` objects with `ingressClassName: alb` and creates/updates ALBs.

**Every command uses `--kube-context dalgo-prod-af`.** Same release name/namespace as Mumbai prod.

One ALB in Africa (no public ALB: nothing here is internet-facing):

| ALB group (`group.name`)    | Scheme   | Host                                    | Ingress source                              |
|-----------------------------|----------|-----------------------------------------|---------------------------------------------|
| `dalgo-prod-af-internal` | internal | airbyte-prod-af-internal.dalgo.org   | airbyte/helm/airbyte-internal-ingress.yaml  |

Only the Mumbai prod EC2 `dalgo-production-arm` (/32, over peering) and the Africa VPC may connect (`inbound-cidrs` on the Ingress).

## Prerequisites (from Terraform)

```bash
# run from dalgo-prod-cluster-africa/
terraform -chdir=bootstrap output -raw vpc_id
terraform -chdir=cluster/terraform output acm_certificate_arn      # goes into the Airbyte Ingress
terraform -chdir=cluster/terraform output acm_validation_records   # same account as Mumbai prod's *.dalgo.org cert: usually the same CNAME, already in Cloudflare
```

The cert must be **Issued** (ACM console, af-south-1) before the Ingress is applied.

The IAM role and its Pod Identity association (`kube-system/aws-load-balancer-controller`) come from
Terraform; no service account annotation. Keep the service account name exactly `aws-load-balancer-controller`.

Subnet tags (set in `bootstrap/`; the controller discovers subnets by these):

- public subnets: `kubernetes.io/role/elb = 1`
- private subnets: `kubernetes.io/role/internal-elb = 1`

## Install

```bash
helm repo add eks https://aws.github.io/eks-charts
helm repo update eks

# <vpc_id>: terraform -chdir=bootstrap output -raw vpc_id
helm --kube-context dalgo-prod-af upgrade --install aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system \
  --set clusterName=dalgo-prod-af-cluster \
  --set region=af-south-1 \
  --set vpcId=<vpc_id> \
  --set serviceAccount.create=true \
  --set serviceAccount.name=aws-load-balancer-controller \
  --set defaultTags.Product=dalgo \
  --set defaultTags.Environment=production \
  --set defaultTags.ManagedBy=aws-load-balancer-controller \
  --version 1.13.0
# defaultTags go on every ALB / target group / SG the controller creates and win over Ingress tags,
# so Name and Subset are set per Ingress (alb.ingress.kubernetes.io/tags), not here.
```

Check:

```bash
kubectl --context dalgo-prod-af -n kube-system get deploy aws-load-balancer-controller
kubectl --context dalgo-prod-af -n kube-system logs deploy/aws-load-balancer-controller | tail
```

## After the Airbyte Ingress is applied

```bash
kubectl --context dalgo-prod-af get ingress -A    # ADDRESS column = ALB hostname
```

- Route53 private zone `airbyte-prod-af-internal.dalgo.org`
  (`terraform -chdir=cluster/terraform output airbyte_internal_zone_id`): alias A record (apex) -> internal ALB.
  Associate the zone with the Mumbai prod VPC by hand (`../../README.md`), so the backend EC2 resolves it.
- No Cloudflare records: the name is private.

## Notes

- `load-balancer-attributes` (idle timeout) is per ALB. Every Ingress in a group must have the same value.
- Use `pathType: Prefix`. `ImplementationSpecific` with path `/` is an exact match on ALB.
- Deleting an Ingress (or the last Ingress in a group) deletes its ALB. Delete Ingresses before
  `terraform destroy`, otherwise the ALB and its security groups are left behind and block VPC cleanup.
