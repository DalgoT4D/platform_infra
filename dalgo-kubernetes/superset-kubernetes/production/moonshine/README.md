# release-name
noora

# apply the env
kubectl apply -f superset-env.yaml

# install/upgrade
helm upgrade --install --values values5.0.0.yaml  moonshine  superset/superset --version 0.14.1 --namespace superset --debug

# uninstall
helm uninstall moonshine -n superset

# port forward
kubectl port-forward service/moonshine  8088:8088 --namespace superset