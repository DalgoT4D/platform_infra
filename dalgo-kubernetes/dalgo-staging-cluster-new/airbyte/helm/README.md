# Airbyte 1.8.3

Database is the external staging RDS and storage is S3; both are already set in `values1.8.3.yaml`
(`# MIGRATION` comments record the old-account values).

## Install

```bash
helm repo add airbyte https://airbytehq.github.io/helm-charts
helm repo update airbyte

# namespace first: the secret below goes into it
kubectl create namespace airbyte

# secrets: copy airbyte-config-secrets.example.yaml, fill in, never commit the filled file
kubectl apply -n airbyte -f airbyte-config-secrets.yaml

helm upgrade --install airbyte airbyte/airbyte -n airbyte --values values1.8.3.yaml --version 1.8.3
```

Uninstall:

```bash
helm uninstall airbyte -n airbyte
```

## Internal ALB

The AWS Load Balancer Controller is installed once per cluster: see
`../../cluster/ingress/aws-load-balancer-controller.md`. Its IAM role and Pod Identity
association come from terraform, so no eksctl / IAM policy steps are needed.

```bash
kubectl apply -f airbyte-internal-ingress.yaml
```

Then point the private Route53 zone `airbyte-staging-internal.dalgo.org`
(`terraform output airbyte_internal_zone_id`) at the ALB with an alias record.
