Helm chart used from kube-prometheus-stack from prometheus-community.

Version used here is : 69.3.1

There are only two changes done to original values.yaml

 1. New Storage class is created. (gp3.yaml)
2. Storage Spec.
3. Service Account for prometheus.

Rest all values are default.