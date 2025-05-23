# terraform plan
# terraform apply -auto-approve

ROLE="arn:aws:iam::024209611402:role/AWSReservedSSO_EKSClusterManagement_4e8ae473c740206e"
CLUSTER_NAME="dalgo-prod-cluster"
REGION="ap-south-1"

eksctl create iamidentitymapping \
    --cluster $CLUSTER_NAME \
    --arn $ROLE \
    --username admin \
    --group system:masters

# aws eks update-kubeconfig --name $CLUSTER_NAME --region $REGION --role-arn $ROLE  

# aws eks update-kubeconfig --region $REGION --name $CLUSTER_NAME

# add AWS elb to expose Airbyte webapp service
# kubectl apply -f loadbalancer.yaml -n airbyte
