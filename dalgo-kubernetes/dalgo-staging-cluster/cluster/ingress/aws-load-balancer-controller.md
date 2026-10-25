# AWS Load Balancer Controller (ALB ingress) - new staging cluster

Replaces ingress-nginx + NLB + cert-manager. The controller watches `Ingress`
objects with `ingressClassName: alb` and creates/updates ALBs. It is not in the
request path: traffic goes ALB -> pod IPs directly.

Two ALBs on staging:

| ALB group (`group.name`) | Scheme          | Hosts                                         | Ingress source                                        |
|--------------------------|-----------------|-----------------------------------------------|-------------------------------------------------------|
| `dalgo-staging-public`   | internet-facing | demosuperset.dalgo.org, grafana-staging.dalgo.org | superset/demosuperset/values6.0.0.yaml, monitoring/values.yaml |
| `dalgo-staging-internal` | internal        | airbyte-staging-internal.dalgo.org            | airbyte/helm/airbyte-internal-ingress.yaml            |

## Prerequisites (from cluster/terraform)

```bash
cd cluster/terraform
terraform output vpc_id
terraform output acm_certificate_arn      # replace <acm_certificate_arn> in the Ingress files
terraform output acm_validation_records   # add these CNAMEs in Cloudflare (DNS only), once
```

The IAM role and its Pod Identity association (`kube-system/aws-load-balancer-controller`)
come from terraform, so no service account annotation is needed. Keep the service account
name exactly `aws-load-balancer-controller`.

Subnet tags (added by terraform, `public_subnet_ids` / `private_subnet_ids` in tfvars; the controller discovers subnets by these):

- public subnets: `kubernetes.io/role/elb = 1`
- private subnets: `kubernetes.io/role/internal-elb = 1`

## Install

```bash
helm repo add eks https://aws.github.io/eks-charts
helm repo update eks

helm upgrade --install aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system \
  --set clusterName=dalgo-staging-cluster \
  --set region=ap-south-1 \
  --set vpcId=<vpc_id> \
  --set serviceAccount.create=true \
  --set serviceAccount.name=aws-load-balancer-controller \
  --set defaultTags.Product=dalgo \
  --set defaultTags.Environment=staging \
  --set defaultTags.ManagedBy=aws-load-balancer-controller \
  --version 1.13.0
# defaultTags go on every ALB / target group / SG the controller creates and win over Ingress tags,
# so Name and Subset are set per Ingress (alb.ingress.kubernetes.io/tags), not here.
```

Check:

```bash
kubectl -n kube-system get deploy aws-load-balancer-controller
kubectl -n kube-system logs deploy/aws-load-balancer-controller | tail
```

## After the Ingresses are applied

```bash
kubectl get ingress -A    # ADDRESS column = ALB hostname
```

- Cloudflare: CNAME `demosuperset` and `grafana-staging` -> public ALB hostname
- Route53 private zone `airbyte-staging-internal.dalgo.org` (`terraform output airbyte_internal_zone_id`):
  alias A record (apex) -> internal ALB

## Notes

- `load-balancer-attributes` (idle timeout) is per ALB. Every Ingress in a group
  must have the same value, otherwise the controller refuses to reconcile the group.
- Use `pathType: Prefix`. `ImplementationSpecific` with path `/` is an exact match on ALB.
- Health check defaults to `/` expecting 200; set `healthcheck-path` for apps that redirect.
- Deleting an Ingress (or the last Ingress in a group) deletes its ALB.
  Delete Ingresses before `terraform destroy`, otherwise the ALBs and their
  security groups are left behind and block VPC cleanup.
