########################################
# AMI (Canonical Ubuntu, arm64)
########################################

data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = [var.ami_name_filter]
  }

  filter {
    name   = "architecture"
    values = ["arm64"]
  }
}

########################################
# Instance
########################################

resource "aws_instance" "staging" {
  ami           = data.aws_ami.ubuntu.id
  instance_type = var.instance_type
  subnet_id     = local.bootstrap.public_subnet_ids[var.subnet_az]
  key_name      = var.key_pair_name # created by hand in the EC2 console

  vpc_security_group_ids = [
    local.bootstrap.staging_ec2_sg_id,
    local.bootstrap.cloudflare_https_sg_id,
  ]

  root_block_device {
    volume_type           = "gp3"
    volume_size           = var.root_volume_size
    iops                  = 3000
    throughput            = 125
    encrypted             = var.root_volume_encrypted
    delete_on_termination = true
  }

  # IMDSv2 only; hop limit 2 so containers on the box can reach it
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 2
  }

  tags = {
    Name = var.instance_name
  }

  lifecycle {
    # A newer Ubuntu AMI must not replace the running box
    ignore_changes = [ami]
  }
}
