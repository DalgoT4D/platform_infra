helm uninstall airbyte -n airbyte

<!-- helm upgrade --install airbyte airbyte/airbyte --namespace airbyte --values values1.7.0.yaml --version 1.7.0 -->

helm upgrade --install airbyte airbyte/airbyte --namespace airbyte --values values1.8.3.yaml --version 1.8.3


## setting up aws load balancer controller

https://docs.aws.amazon.com/eks/latest/userguide/lbc-helm.html

1. Create AWSLoadBalancerControllerIAMPolicy with the permissions aws_loadbalancer_controller_iam_policy.json

2. eksctl create iamserviceaccount \
    --cluster=<cluster-name> \
    --namespace=kube-system \
    --name=aws-load-balancer-controller-prod \
    --attach-policy-arn=arn:aws:iam::<AWS_ACCOUNT_ID>:policy/AWSLoadBalancerControllerIAMPolicy \
    --override-existing-serviceaccounts \
    --region <aws-region-code> \
    --approve

3. helm repo add eks https://aws.github.io/eks-charts

4. helm repo update eks

5. helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system \
  --set clusterName=my-cluster \
  --set serviceAccount.create=false \
  --set serviceAccount.name=aws-load-balancer-controller-prod \
  --set vpcId=$VPC_ID \
  --version 1.13.0

helm upgrade aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system \
  --set clusterName=my-cluster \
  --set serviceAccount.create=false \
  --set serviceAccount.name=aws-load-balancer-controller-prod \
  --set region=ap-south-1 \
  --set vpcId=$VPC_ID \
  --version 1.13.0

