# Create the namespace first: the service and endpoint below go into it

kubectl --context dalgo-staging-af create namespace prefect-staging

# Setup a service to connect to external prefect (same file as Mumbai)

kubectl --context dalgo-staging-af apply -f ../../../dalgo-staging-cluster/prefect/prefect-workers/prefect-external-service.yaml

# Setup an endpoint to map cluster DNS to the service created above

kubectl --context dalgo-staging-af apply -f prefect-external-service-endpoint.yaml

# Install the prefect worker

helm repo add prefect https://prefecthq.github.io/prefect-helm

helm repo update

helm --kube-context dalgo-staging-af install prefect-worker prefect/prefect-worker --namespace=prefect-staging -f values.yaml --version 2025.1.30204105

helm --kube-context dalgo-staging-af upgrade --install prefect-worker prefect/prefect-worker -n prefect-staging -f values.yaml --version 2025.1.30204105

helm --kube-context dalgo-staging-af uninstall prefect-worker -n prefect-staging
