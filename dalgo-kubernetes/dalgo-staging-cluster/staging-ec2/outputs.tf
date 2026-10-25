output "instance_id" {
  value = aws_instance.staging.id
}

output "ami" {
  description = "AMI the box was launched from"
  value       = aws_instance.staging.ami
}

output "public_ip" {
  description = "Auto-assigned public IP (changes on stop/start). Point the Cloudflare A records here."
  value       = aws_instance.staging.public_ip
}

output "private_ip" {
  description = "In-VPC IP. prefect/prefect-workers external endpoint uses this."
  value       = aws_instance.staging.private_ip
}

output "ssh_command" {
  value = "ssh -i <private-key> ubuntu@${aws_instance.staging.public_ip}"
}
