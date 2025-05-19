# ingress controller (with loadbalancer) for the cluster

helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update

helm install nginx-ingress ingress-nginx/ingress-nginx \
  --namespace ingress-nginx \
  --create-namespace \
  --set controller.service.type=LoadBalancer \
  --set controller.service.externalTrafficPolicy=Local \
  --set controller.allowSnippetAnnotations=true

helm uninstall nginx-ingress -n ingress-nginx


# set this in the configmap

kubectl edit configmap nginx-ingress-ingress-nginx-controller -n ingress-nginx

add under data "annotations-risk-level: Critical"

# logs of ingress controller

 kubectl logs -n ingress-nginx -l app.kubernetes.io/name=ingress-nginx