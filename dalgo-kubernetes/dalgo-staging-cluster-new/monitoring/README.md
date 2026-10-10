Helm chart used: kube-prometheus-stack from prometheus-community (staging runs 69.4.1).

Changes from the chart's default values.yaml:

1. New storage class `gp3` (storageclass-gp3.yaml), backed by the EBS CSI driver.
2. Storage spec for Prometheus, Alertmanager and Grafana (all on gp3).
3. Service account for Prometheus.
4. Grafana ingress on the shared internet-facing ALB (was nginx + cert-manager).

## Install

# storage class (needs the aws-ebs-csi-driver add-on with its Pod Identity role working)
kubectl apply -f storageclass-gp3.yaml

# grafana admin secret (copy the example, fill in, never commit the filled file)
kubectl create namespace monitoring
kubectl apply -f grafana-admin-secret.yaml

# before the first install: replace <acm_certificate_arn> in values.yaml
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update prometheus-community
helm upgrade --install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
  -n monitoring -f values.yaml --version 69.4.1

## Not copied from the old cluster

pvs/ and pvcs/ bound a static PV to an EBS volume in the old account (vol-0a2377b85a9597f54)
with the in-tree gp2-prod class. Neither exists in the new account; the gp3 PVCs above are
created dynamically instead.
