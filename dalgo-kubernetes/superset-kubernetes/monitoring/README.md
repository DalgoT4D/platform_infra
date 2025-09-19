helm repo add prometheus-community https://prometheus-community.github.io/helm-charts

helm install prometheus-stack prometheus-community/kube-prometheus-stack -n monitoring -f values.yaml

helm upgrade prometheus-stack prometheus-community/kube-prometheus-stack -n monitoring -f values.yaml

helm uninstall prometheus-stack -n monitoring


# install ebs csi driver 
helm repo add aws-ebs-csi-driver https://kubernetes-sigs.github.io/aws-ebs-csi-driver
helm repo update
helm install aws-ebs-csi-driver aws-ebs-csi-driver/aws-ebs-csi-driver --namespace kube-system 
helm uninstall aws-ebs-csi-driver -n kube-system

## attach the role to ebs driver service accounts that has the right permissions to create volumes etc
..
kind: ServiceAccount
metadata:
  annotations:
    eks.amazonaws.com/role-arn: <role-arn-goes-here>
..

In the role that you use, you will need to udpate the trust policy so that cluster service acount can assume the role to create volumes etc.


# expose to https
kubectl create secret tls grafana-tls-secret \
  --cert=dalgo.org.ssl.pem \
  --key=dalgo.org.ssl.key \
  --namespace=monitoring

kubectl apply -f ingress.yaml


update the DNS record for the subdomain