# Create the namespace first: the service and endpoint below go into it

kubectl create namespace prefect-staging

# Setup a service to connect to external prefect

kubectl apply -f prefect-external-service.yaml

# Setup an endpoint to map cluster DNS to the service created above

kubectl apply -f prefect-external-service-endpoint.yaml

# Install the prefect worker

helm repo add prefect https://prefecthq.github.io/prefect-helm

helm repo update

helm install prefect-worker prefect/prefect-worker --namespace=prefect-staging -f values3.1.15.yaml --version 2025.1.30204105

helm upgrade --install prefect-worker prefect/prefect-worker -n prefect-staging -f values3.1.15.yaml --version 2025.1.30204105

helm uninstall prefect-worker -n prefect-staging