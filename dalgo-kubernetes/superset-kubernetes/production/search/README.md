# release-name
search

# apply the env
kubectl apply -f superset-env.yaml

# install/upgrade
helm upgrade --install --values values4.1.1.yaml  search superset/superset --version 0.14.1 --namespace superset --debug

# uninstall
helm uninstall search -n superset 

# port forward
kubectl port-forward service/search  8088:8088 --namespace superset