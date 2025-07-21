# release-name
atecf

# apply the env
kubectl apply -f superset-env.yaml

# install/upgrade
helm upgrade --install --values values4.1.1.yaml  atecf superset/superset --version 0.14.1 --namespace superset --debug

# uninstall
helm uninstall atecf -n superset 

# port forward
kubectl port-forward service/atecf  8088:8088 --namespace superset