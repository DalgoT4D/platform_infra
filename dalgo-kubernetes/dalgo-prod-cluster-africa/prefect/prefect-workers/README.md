# Prefect workers (prod Africa)

**Always pass `--kube-context dalgo-prod-af`.** Namespace `prefect` and release `prefect-worker` are the same as
Mumbai prod.

The Prefect server stays in Mumbai (`dalgo-production-arm`, 172.31.2.21:4200). Africa runs only the worker; it polls
its own pool and starts flow-run pods in this cluster. Needs the peering + Mumbai manual steps done
(`../../README.md`), otherwise the worker can't reach the server.

## 1. Work pool (on dalgo-production-arm)

Copy `base_job_template.json` to the EC2 (job image from the af-south-1 ECR cache, namespace `prefect`), then:

```bash
prefect work-pool create prod_af_eks_dalgo_work_pool --type kubernetes --base-job-template base_job_template.json
prefect work-pool ls
```

## 2. Service + EndpointSlice (in-cluster name for the Mumbai Prefect server)

```bash
kubectl --context dalgo-prod-af create namespace prefect
kubectl --context dalgo-prod-af apply -f prefect-external-service.yaml
cp prefect-external-service-endpoint.example.yaml prefect-external-service-endpoint.yaml
kubectl --context dalgo-prod-af apply -f prefect-external-service-endpoint.yaml

# reachability over the peering (expect {"status": "healthy"} or similar)
kubectl --context dalgo-prod-af -n prefect run curl --rm -it --restart=Never --image=curlimages/curl -- \
  curl -s http://prefect-server-external.prefect.svc.cluster.local:4200/api/health
```

## 3. Worker

```bash
helm repo add prefect https://prefecthq.github.io/prefect-helm
helm repo update prefect

helm --kube-context dalgo-prod-af upgrade --install prefect-worker prefect/prefect-worker \
  -n prefect -f values.yaml --version 2025.1.30204105

kubectl --context dalgo-prod-af -n prefect logs deploy/prefect-worker | tail
```

## Uninstall

```bash
helm --kube-context dalgo-prod-af uninstall prefect-worker -n prefect
# on dalgo-production-arm
prefect work-pool delete prod_af_eks_dalgo_work_pool
```
