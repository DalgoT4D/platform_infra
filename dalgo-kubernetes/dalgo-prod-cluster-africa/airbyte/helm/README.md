# Airbyte (prod Africa)

**Always pass `--kube-context dalgo-prod-af`.** Namespace `airbyte` and release `airbyte` are the same as Mumbai
prod: the wrong context changes Mumbai prod.

## Before the first install

1. **DB user** on the Africa prod RDS (`terraform -chdir=../../prod-rds output -raw endpoint`). The RDS is private:
   use a throwaway pod in the cluster.

   ```bash
   kubectl --context dalgo-prod-af run psql --rm -it --restart=Never --image=postgres:18 -- \
     psql "host=<AFRICA_RDS_ENDPOINT> user=postgres dbname=postgres sslmode=require"
   ```

   ```sql
   CREATE USER airbyte_user WITH PASSWORD '<AFRICA_AIRBYTE_DB_PASSWORD>' CREATEDB;
   CREATE DATABASE airbyte OWNER airbyte_user;
   ```

   Password: `openssl rand -base64 24 | tr -d '/@"+='`, store it in the vault.
2. `values1.8.3.yaml`: replace `<AFRICA_RDS_ENDPOINT>` (2 places).
3. `airbyte-internal-ingress.yaml`: replace `<AFRICA_ACM_CERT_ARN>` (`terraform -chdir=../../cluster/terraform output -raw acm_certificate_arn`).
   The cert must be **Issued** first.
4. `cp airbyte-config-secrets.example.yaml airbyte-config-secrets.yaml` (gitignored) and fill:
   - `database-host` = `<AFRICA_RDS_ENDPOINT>`, `database-user` = `airbyte_user`, `database-password` = `<AFRICA_AIRBYTE_DB_PASSWORD>`,
     `database-port` = `5432`; `DATABASE_USER` / `DATABASE_PASSWORD` = the same user/password
   - `S3_LOG_BUCKET` = `dalgo-prod-af-airbyte`, `S3_LOG_BUCKET_REGION` = `af-south-1`
   - `gcp.json` = same as the Mumbai prod secret (`kubectl --context dalgo-prod -n airbyte get secret airbyte-config-secrets -o jsonpath='{.data.gcp\.json}' | base64 -d`)
   - leave every AWS key empty: S3 access is the Pod Identity role `dalgo-prod-af-eks-airbyte-s3`.

## Install

```bash
helm repo add airbyte https://airbytehq.github.io/helm-charts
helm repo update airbyte

kubectl --context dalgo-prod-af create namespace airbyte
kubectl --context dalgo-prod-af apply -n airbyte -f airbyte-config-secrets.yaml

helm --kube-context dalgo-prod-af upgrade --install airbyte airbyte/airbyte \
  --namespace airbyte --values values1.8.3.yaml --version 1.8.3

kubectl --context dalgo-prod-af -n airbyte get pods
```

## Internal ALB

Needs the AWS Load Balancer Controller (`../../cluster/ingress/aws-load-balancer-controller.md`).

```bash
kubectl --context dalgo-prod-af apply -f airbyte-internal-ingress.yaml
kubectl --context dalgo-prod-af -n airbyte get ingress   # ADDRESS = internal ALB hostname
```

Then in Route 53, private zone `airbyte-prod-af-internal.dalgo.org`
(`terraform -chdir=../../cluster/terraform output -raw airbyte_internal_zone_id`): alias A record (apex) -> the ALB.

Check from `dalgo-production-arm` (after the Mumbai manual peering steps):

```bash
curl -s https://airbyte-prod-af-internal.dalgo.org/api/v1/health
```

## Uninstall

```bash
kubectl --context dalgo-prod-af delete -f airbyte-internal-ingress.yaml   # wait until the ALB is gone
helm --kube-context dalgo-prod-af uninstall airbyte -n airbyte
```
