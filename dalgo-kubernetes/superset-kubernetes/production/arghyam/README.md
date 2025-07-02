# release-name
arghyam

# apply the env
kubectl apply -f superset-arghyam-env.yaml

# install/upgrade
helm upgrade --install --values values4.1.1.yaml  arghyam superset/superset --version 0.14.1 --namespace superset --debug

# uninstall
helm uninstall arghyam -n superset 

# port forward
kubectl port-forward service/arghyam  8088:8088 --namespace superset