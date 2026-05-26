# release-name
noora

# apply the env
kubectl apply -f superset-env.yaml

# install/upgrade
<!-- helm upgrade --install --values values4.1.1.yaml  noora-oauth superset/superset --version 0.14.1 --namespace superset --debug -->
helm upgrade --install --values values5.0.0.yaml  noora-oauth  superset/superset --version 0.14.1 --namespace superset --debug

# uninstall
helm uninstall noora-oauth -n superset

# port forward
kubectl port-forward service/noora-oauth  8088:8088 --namespace superset