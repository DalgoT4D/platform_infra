output "peering_connection_id" {
  value = aws_vpc_peering_connection.africa_mumbai.id
}

output "peering_status" {
  description = "pending-acceptance until manual step 1 is done; then active (refresh: terraform apply -refresh-only)"
  value       = aws_vpc_peering_connection.africa_mumbai.accept_status
}

output "mumbai_ec2_private_ip" {
  description = "Fill <MUMBAI_EC2_PRIVATE_IP> in airbyte/helm/airbyte-internal-ingress.yaml (/32) and the Prefect EndpointSlice"
  value       = var.mumbai_ec2_private_ip
}

output "routes" {
  value = { for k, r in aws_route.africa_to_mumbai : k => "${r.route_table_id} ${r.destination_cidr_block}" }
}

# Mumbai prod is changed BY HAND. These are the exact commands (also in ../README.md).
# Run them yourself, one at a time, reading each one. Undo commands are in ../README.md (teardown).
output "mumbai_manual_steps" {
  value = <<-EOT
    # 1. Accept the peering request (Mumbai side)
    aws ec2 accept-vpc-peering-connection --region ap-south-1 --profile ${var.aws_profile} \
      --vpc-peering-connection-id ${aws_vpc_peering_connection.africa_mumbai.id}
    aws ec2 create-tags --region ap-south-1 --profile ${var.aws_profile} \
      --resources ${aws_vpc_peering_connection.africa_mumbai.id} --tags Key=Name,Value=dalgo-prod-af-mumbai-peering Key=Side,Value=accepter

    # 2. Route Mumbai -> Africa in the route table of dalgo-production-arm's subnet (VPC main table)
    aws ec2 create-route --region ap-south-1 --profile ${var.aws_profile} \
      --route-table-id ${var.mumbai_route_table_id} \
      --destination-cidr-block ${local.africa.vpc_cidr} \
      --vpc-peering-connection-id ${aws_vpc_peering_connection.africa_mumbai.id}

    # 3. Prefect server ${var.prefect_port} on dalgo-production-arm from the Africa VPC (workers + flow-run pods)
    aws ec2 authorize-security-group-ingress --region ap-south-1 --profile ${var.aws_profile} \
      --group-id ${var.mumbai_ec2_sg_id} \
      --ip-permissions 'IpProtocol=tcp,FromPort=${var.prefect_port},ToPort=${var.prefect_port},IpRanges=[{CidrIp=${local.africa.vpc_cidr},Description="Prefect from Africa prod EKS"}]'

    # 4. Africa Airbyte private zone -> also the Mumbai prod VPC (backend resolves the internal ALB name)
    aws route53 associate-vpc-with-hosted-zone --profile ${var.aws_profile} \
      --hosted-zone-id ${local.africa_eks.airbyte_internal_zone_id} \
      --vpc VPCRegion=ap-south-1,VPCId=${var.mumbai_vpc_id}

    # 5. On dalgo-production-arm, only if `sudo ufw status` says active:
    #    sudo ufw allow from ${local.africa.vpc_cidr} to any port ${var.prefect_port} proto tcp

    # Then: peering_accepted = true in terraform.tfvars, and apply again (Africa -> Mumbai routes).
  EOT
}
