# release-name
sneha

# apply the env
kubectl apply -f superset-env.yaml

# install/upgrade
<!-- helm upgrade --install --values values4.1.1.yaml  sneha superset/superset --version 0.14.1 --namespace superset --debug -->
helm upgrade --install --values values5.0.0.yaml  sneha superset/superset --version 0.14.1 --namespace superset --debug
# uninstall
helm uninstall sneha -n superset 

# port forward
kubectl port-forward service/sneha  8088:8088 --namespace superset