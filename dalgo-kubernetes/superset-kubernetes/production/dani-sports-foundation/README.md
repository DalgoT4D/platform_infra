
# release-name
dani

# apply the env
kubectl apply -f superset-env.yaml

# install/upgrade
<!-- helm upgrade --install --values values4.1.1.yaml  dani superset/superset --version 0.14.1 --namespace superset --debug -->

helm upgrade --install --values values6.0.0.yaml  dani superset/superset --version 0.14.1 --namespace superset --debug
# uninstall
helm uninstall dani -n superset 

# port forward
kubectl port-forward service/dani  8088:8088 --namespace superset