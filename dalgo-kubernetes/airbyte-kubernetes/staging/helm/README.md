helm uninstall airbyte -n airbyte

helm upgrade --install airbyte airbyte/airbyte --namespace airbyte --values values1.7.0.yaml --version 1.7.0