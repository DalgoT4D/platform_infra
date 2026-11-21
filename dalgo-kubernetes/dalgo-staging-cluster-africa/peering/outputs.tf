output "peering_connection_id" {
  value = aws_vpc_peering_connection.mumbai_africa.id
}

output "mumbai_ec2_private_ip" {
  description = "Fill <MUMBAI_EC2_PRIVATE_IP> in airbyte/helm/airbyte-internal-ingress.yaml (/32) and the Prefect EndpointSlice"
  value       = data.terraform_remote_state.mumbai_staging_ec2.outputs.private_ip
}

output "routes" {
  value = {
    mumbai_to_africa = { for k, r in aws_route.mumbai_to_africa : k => "${r.route_table_id} ${r.destination_cidr_block}" }
    africa_to_mumbai = { for k, r in aws_route.africa_to_mumbai : k => "${r.route_table_id} ${r.destination_cidr_block}" }
  }
}
