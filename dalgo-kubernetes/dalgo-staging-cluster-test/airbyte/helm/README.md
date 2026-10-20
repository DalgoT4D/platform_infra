helm repo add airbyte https://airbytehq.github.io/helm-charts
helm repo update airbyte

# namespace first: the secret below goes into it
kubectl create namespace airbyte

# secrets (copy the example, fill in, never commit the filled file)
kubectl apply -n airbyte -f airbyte-config-secrets.yaml

helm upgrade --install airbyte airbyte/airbyte --namespace airbyte --create-namespace --values values1.8.3.yaml --version 1.8.3

helm uninstall airbyte -n airbyte

## Before the first install (new account)

- `values1.8.3.yaml`: replace `<new-account-rds-endpoint>` (2 places) and `<new-account-bucket>` (lines marked `# MIGRATION`).
- `airbyte-internal-ingress.yaml`: replace `<acm_certificate_arn>` with `terraform output acm_certificate_arn` (cluster/terraform).

## Internal ALB

The AWS Load Balancer Controller is installed once per cluster: see
`../../cluster/ingress/aws-load-balancer-controller.md`. Its IAM role and Pod Identity
association come from terraform, so the old eksctl / IAM policy steps are no longer needed.

kubectl apply -f airbyte-internal-ingress.yaml

Then point the private Route53 zone `airbyte-staging-internal.dalgo.org`
(`terraform output airbyte_internal_zone_id`) at the ALB with an alias record.
