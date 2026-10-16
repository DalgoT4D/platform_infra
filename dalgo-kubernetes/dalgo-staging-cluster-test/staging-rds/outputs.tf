output "endpoint" {
  description = "Host for DATABASE_URL / airbyte / superset values"
  value       = aws_db_instance.staging.address
}

output "port" {
  value = aws_db_instance.staging.port
}

output "master_username" {
  value = aws_db_instance.staging.username
}
