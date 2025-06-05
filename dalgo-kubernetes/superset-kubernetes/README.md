Running superset 4.1.1

helm repo add superset https://apache.github.io/superset 

kubectl apply -f superset-env.yaml

helm upgrade --install --values values4.1.1.yaml  superset superset/superset --version 0.14.1 --namespace superset --debug