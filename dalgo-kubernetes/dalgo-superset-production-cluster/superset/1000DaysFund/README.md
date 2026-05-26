# release-name
tdf-1000daysfund

# apply the env
kubectl apply -f superset-env.yaml

# install/upgrade
helm upgrade --install --values values5.0.0.yaml tdf-1000daysfund superset/superset --version 0.14.1 --namespace superset --debug

# uninstall
helm uninstall tdf-1000daysfund -n superset

# port forward
kubectl port-forward service/tdf-1000daysfund 8088:8088 --namespace superset
