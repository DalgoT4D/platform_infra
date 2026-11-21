output "endpoint" {
  description = "Airbyte DB host: <AFRICA_RDS_ENDPOINT> in airbyte/helm/values1.8.3.yaml + database-host in airbyte-config-secrets"
  value       = aws_db_instance.staging.address
}

output "port" {
  value = aws_db_instance.staging.port
}

output "master_username" {
  value = aws_db_instance.staging.username
}
