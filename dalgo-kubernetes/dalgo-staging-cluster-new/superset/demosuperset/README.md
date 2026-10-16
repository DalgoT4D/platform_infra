# release-name
demosuperset

# namespace first: the env secret below goes into it
kubectl create namespace superset

# apply the env
kubectl apply -f superset-env.yaml

# before the first install: replace <acm_certificate_arn> in values6.0.0.yaml
# (terraform output acm_certificate_arn in cluster/terraform). Ingress is now an ALB.

# install/upgrade
helm upgrade --install --values values6.0.0.yaml  demosuperset superset/superset --version 0.14.1 --namespace superset --create-namespace --debug

# uninstall
helm uninstall demosuperset -n superset

# port forward
kubectl port-forward service/demosuperset  8088:8088 --namespace superset
