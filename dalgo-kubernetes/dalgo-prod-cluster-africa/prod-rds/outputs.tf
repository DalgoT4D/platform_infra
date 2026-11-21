output "endpoint" {
  description = "Airbyte DB host: <AFRICA_RDS_ENDPOINT> in airbyte/helm/values1.8.3.yaml + database-host in airbyte-config-secrets"
  value       = aws_db_instance.prod.address
}

output "port" {
  value = aws_db_instance.prod.port
}

output "master_username" {
  value = aws_db_instance.prod.username
}
