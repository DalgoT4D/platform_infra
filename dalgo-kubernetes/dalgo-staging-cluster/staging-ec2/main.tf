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
# Instance role
########################################

# Lets the backend call S3 / SES / Secrets Manager without static IAM-user keys.
# boto3 on the box picks the credentials up from instance metadata (hop limit 2 below
# so Docker containers can reach it).
resource "aws_iam_role" "staging_ec2" {
  name = "${var.instance_name}-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })

  tags = {
    Name = "${var.instance_name}-role"
  }
}

resource "aws_iam_instance_profile" "staging_ec2" {
  name = "${var.instance_name}-profile"
  role = aws_iam_role.staging_ec2.name
}

########################################
# S3: images bucket (org logos, dashboard widget images) -> backend S3_IMAGES_BUCKET
########################################

resource "aws_s3_bucket" "images" {
  bucket = "dalgo-staging-images"

  tags = {
    Name = "dalgo-staging-images"
  }
}

# The backend returns plain https://<bucket>.s3.<region>.amazonaws.com/<key> URLs
# (ddpui/utils/s3_utils.py), so objects must be publicly readable. ACLs stay blocked;
# public read comes only from the bucket policy below.
resource "aws_s3_bucket_public_access_block" "images" {
  bucket = aws_s3_bucket.images.id

  block_public_acls       = true
  ignore_public_acls      = true
  block_public_policy     = false
  restrict_public_buckets = false
}

resource "aws_s3_bucket_policy" "images_public_read" {
  bucket = aws_s3_bucket.images.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "PublicReadObjects"
      Effect    = "Allow"
      Principal = "*"
      Action    = "s3:GetObject"
      Resource  = "${aws_s3_bucket.images.arn}/*"
    }]
  })

  depends_on = [aws_s3_bucket_public_access_block.images]
}

resource "aws_iam_role_policy" "s3_images" {
  name = "s3-images-read-write-delete"
  role = aws_iam_role.staging_ec2.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
        Resource = "${aws_s3_bucket.images.arn}/*"
      },
      {
        Effect   = "Allow"
        Action   = ["s3:ListBucket"]
        Resource = aws_s3_bucket.images.arn
      },
    ]
  })
}

########################################
# SES: send email from the verified dalgo.org identity (created by hand)
########################################

resource "aws_iam_role_policy" "ses_send" {
  name = "ses-send"
  role = aws_iam_role.staging_ec2.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = ["ses:SendEmail", "ses:SendRawEmail"]
      # identity/* because in sandbox SES also authorizes against the recipient identity
      Resource  = "arn:aws:ses:${var.aws_region}:${var.aws_account_id}:identity/*"
      Condition = { StringLike = { "ses:FromAddress" = "*@dalgo.org" } }
    }]
  })
}

########################################
# Secrets Manager: app-managed secrets. Prefixes match the name generators in
# ddpui/utils/secretsmanager.py. Used only when USE_AWS_SECRETS_MANAGER=True.
########################################

resource "aws_iam_role_policy" "secretsmanager" {
  name = "secretsmanager-app-secrets"
  role = aws_iam_role.staging_ec2.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "secretsmanager:CreateSecret",
        "secretsmanager:GetSecretValue",
        "secretsmanager:DescribeSecret",
        "secretsmanager:UpdateSecret",
        "secretsmanager:PutSecretValue",
        "secretsmanager:DeleteSecret",
      ]
      Resource = [
        for prefix in ["gitrepoAccessToken-", "warehouseCreds-", "supersetCreds-", "dalgoUserSupersetCreds-"] :
        "arn:aws:secretsmanager:${var.aws_region}:${var.aws_account_id}:secret:${prefix}*"
      ]
    }]
  })
}

# Airbyte region connection details (one secret per region, all stored in Mumbai:
# dalgoAirbyteRegion-staging-in, dalgoAirbyteRegion-staging-af, ...). Read-only.
# Kept here (not in dalgo-staging-cluster-africa/peering) so destroying a region's link never cuts Mumbai's own creds.
resource "aws_iam_role_policy" "secretsmanager_airbyte_regions" {
  name = "secretsmanager-airbyte-region-read"
  role = aws_iam_role.staging_ec2.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["secretsmanager:GetSecretValue", "secretsmanager:DescribeSecret"]
      Resource = "arn:aws:secretsmanager:${var.aws_region}:${var.aws_account_id}:secret:dalgoAirbyteRegion-staging-*"
    }]
  })
}

########################################
# Instance
########################################

resource "aws_instance" "staging" {
  ami           = data.aws_ami.ubuntu.id
  instance_type = var.instance_type
  subnet_id     = local.bootstrap.public_subnet_ids[var.subnet_az]
  key_name      = var.key_pair_name # created by hand in the EC2 console

  iam_instance_profile = aws_iam_instance_profile.staging_ec2.name

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

    tags = {
      Name = "${var.instance_name}-root-volume"
    }
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
