# Read by prod-rds/, cluster/terraform and peering/ via terraform_remote_state.

output "vpc_id" {
  value = aws_vpc.main.id
}

output "vpc_cidr" {
  value = aws_vpc.main.cidr_block
}

output "public_subnet_ids" {
  description = "AZ => subnet ID"
  value       = { for az, s in aws_subnet.public : az => s.id }
}

output "private_subnet_ids" {
  description = "AZ => subnet ID"
  value       = { for az, s in aws_subnet.private : az => s.id }
}

output "nat_public_ip" {
  description = "Outbound IP of Africa Airbyte syncs and dbt runs (clients whitelist this on their DBs/warehouses)"
  value       = aws_eip.nat.public_ip
}

output "s3_endpoint_id" {
  description = "S3 gateway endpoint (S3 traffic from both route tables bypasses the NAT)"
  value       = aws_vpc_endpoint.s3.id
}

output "rds_sg_id" {
  description = "prod-rds/: vpc_security_group_ids"
  value       = aws_security_group.rds.id
}

output "ecr_docker_hub_registry" {
  description = "Set as global.image.registry in airbyte/helm/values1.8.3.yaml"
  value       = "${var.aws_account_id}.dkr.ecr.${var.aws_region}.amazonaws.com/${var.ecr_docker_hub_prefix}"
}

# Read by ../peering to add the 172.31.0.0/16 -> peering routes.
output "public_route_table_id" {
  value = aws_route_table.public.id
}

output "private_route_table_id" {
  description = "Nodes, pods, internal ALB and RDS live here"
  value       = aws_route_table.private.id
}
