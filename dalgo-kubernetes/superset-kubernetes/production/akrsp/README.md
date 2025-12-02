# release-name
akrsp

# apply the env
kubectl apply -f superset-akrsp-env.yaml

# install/upgrade
helm upgrade --install --values values4.1.1.yaml akrsp superset/superset --version 0.14.1 --namespace superset --debug

# uninstall
helm uninstall akrsp -n superset

# port forward
kubectl port-forward service/akrsp  8088:8088 --namespace superset