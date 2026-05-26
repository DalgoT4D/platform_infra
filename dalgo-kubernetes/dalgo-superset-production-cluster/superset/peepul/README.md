
# release-name
peepul

# apply the env
kubectl apply -f superset-env.yaml

# install/upgrade
helm upgrade --install --values values5.0.0.yaml  peepul superset/superset --version 0.14.1 --namespace superset --debug
# uninstall
helm uninstall peepul -n superset 

# port forward
kubectl port-forward service/peepul  8088:8088 --namespace superset