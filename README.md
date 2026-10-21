# platform_infra

A set of scripts to set up a freshly provisioned ec2 instance. We may or may not use these scripts in production, but they contain useful information

## Documentation

- [Kubernetes & AWS EKS Networking Architecture Notes](EKS_Networking_Architecture_Notes.md) — how the EKS data plane fits together: worker nodes and the kubelet, the scheduler, the `kube-system` add-ons (VPC CNI, kube-proxy, CoreDNS), service types, requests vs. limits and QoS, the pod lifecycle, and external routing via Ingress and AWS load balancers.
