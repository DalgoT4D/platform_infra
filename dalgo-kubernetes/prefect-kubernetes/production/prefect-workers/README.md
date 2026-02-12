# Setup a service to connect to external prefect

kubectl apply -f prefect-external-service.yaml

# Setup an endpoint to map cluster DNS to the service created above

kubectl apply -f prefect-external-service-endpoint.yaml

# Install the prefect worker

helm repo add prefect https://prefecthq.github.io/prefect-helm

helm repo update

kubectl create namespace prefect

helm install prefect-worker prefect/prefect-worker --namespace=prefect -f values3.1.15.yaml --version 2025.1.30204105

helm upgrade --install prefect-worker prefect/prefect-worker -n prefect -f values3.1.15.yaml --version 2025.1.30204105

helm uninstall prefect-worker -n prefect