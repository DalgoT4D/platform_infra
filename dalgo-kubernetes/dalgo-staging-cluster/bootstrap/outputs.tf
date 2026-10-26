# Read by staging-ec2/ via terraform_remote_state. Copy the IDs into cluster/terraform/terraform.tfvars.

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
  description = "Outbound IP of everything in the private subnets (whitelist this on external DBs/APIs)"
  value       = aws_eip.nat.public_ip
}

output "staging_ec2_sg_id" {
  description = "cluster/terraform: staging_ec2_sg_id and api_whitelist_security_group_ids"
  value       = aws_security_group.staging_ec2.id
}

output "rds_sg_id" {
  description = "cluster/terraform: rds_sg_id"
  value       = aws_security_group.rds.id
}

output "cloudflare_https_sg_id" {
  value = aws_security_group.cloudflare_https.id
}
