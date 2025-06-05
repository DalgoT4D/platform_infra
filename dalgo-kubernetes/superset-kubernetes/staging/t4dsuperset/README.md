# release-name
t4dsuperset

# apply the env
kubectl apply -f superset-env.yaml

# install/upgrade
helm upgrade --install --values values4.1.1.yaml  t4dsuperset superset/superset --version 0.14.1 --namespace superset --debug

# uninstall
helm uninstall t4dsuperset -n superset 

# port forward
kubectl port-forward service/t4dsuperset  8088:8088 --namespace superset