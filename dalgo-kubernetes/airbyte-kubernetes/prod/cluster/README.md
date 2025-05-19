Steps to setup kubectl to point to a cluster

- `brew install awscli`

- configure aws creds using `aws configure --profile <profile-name>`

- Update the kubeconfig to point to a cluster with a preferred aws profile `eksctl utils write-kubeconfig --cluster <cluster-name> --region <region> --profile <aws_profile>`

- Check if the context is present `kubectl config get-contexts`

- Use the new context `kubectl config use-context <context_name>`
