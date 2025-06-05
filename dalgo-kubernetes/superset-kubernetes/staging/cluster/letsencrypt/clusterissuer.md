# install
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.17.0/cert-manager.yaml

# pods
kubectl get pods --namespace cert-manager

# apply the cluster issuer
kubectl apply -f cluster-issuer.yaml