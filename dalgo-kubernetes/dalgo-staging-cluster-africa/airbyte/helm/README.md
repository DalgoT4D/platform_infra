# Africa cluster: always pass --kube-context dalgo-staging-af (same names as Mumbai)

helm repo add airbyte https://airbytehq.github.io/helm-charts
helm repo update airbyte

# namespace first: the secret below goes into it
kubectl --context dalgo-staging-af create namespace airbyte-staging

# secrets (copy the example, fill in, never commit the filled file)
kubectl --context dalgo-staging-af apply -n airbyte-staging -f airbyte-config-secrets.yaml

helm --kube-context dalgo-staging-af upgrade --install airbyte airbyte/airbyte --namespace airbyte-staging --create-namespace --values values1.8.3.yaml --version 1.8.3

helm --kube-context dalgo-staging-af uninstall airbyte -n airbyte-staging

## Before the first install

- Africa RDS: create `airbyte_user` (CREATEDB) and database `airbyte` owned by it.
- `values1.8.3.yaml`: replace `<AFRICA_RDS_ENDPOINT>` (2 places, lines marked `# AFRICA`).
- `airbyte-internal-ingress.yaml`: replace `<AFRICA_ACM_CERT_ARN>` (`terraform output acm_certificate_arn` in cluster/terraform)
  and `<MUMBAI_EC2_PRIVATE_IP>`.

## Internal ALB

The AWS Load Balancer Controller is installed once per cluster: see
`../../cluster/ingress/aws-load-balancer-controller.md`.

kubectl --context dalgo-staging-af apply -f airbyte-internal-ingress.yaml

Then point the private Route53 zone `airbyte-staging-af-internal.dalgo.org`
(`terraform output airbyte_internal_zone_id`) at the ALB with an alias record.
