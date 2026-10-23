########################################
# Subnet group (private subnets only)
########################################

resource "aws_db_subnet_group" "staging" {
  name        = "${var.identifier}-subnet-group"
  description = "Private subnets for ${var.identifier}"
  subnet_ids  = values(local.bootstrap.private_subnet_ids)
}

########################################
# Parameter group
########################################

resource "aws_db_parameter_group" "staging" {
  name        = "${var.identifier}-pg-${var.engine_version}-param-group"
  family      = "postgres${var.engine_version}"
  description = "Dalgo staging RDS parameter group for postgres ${var.engine_version}"

  # static parameter: takes effect only after a reboot
  parameter {
    name         = "max_connections"
    value        = var.max_connections
    apply_method = "pending-reboot"
  }

  lifecycle {
    create_before_destroy = true
  }
}

########################################
# Instance
########################################

resource "aws_db_instance" "staging" {
  identifier = var.identifier
  engine     = "postgres"

  # null: new empty DB. Set: restore from that snapshot (databases, users and their passwords come with it).
  snapshot_identifier = var.snapshot_identifier

  engine_version = var.engine_version
  instance_class = var.instance_class

  allocated_storage = var.allocated_storage
  storage_type      = "gp3"
  storage_encrypted = true # default aws/rds KMS key

  db_subnet_group_name   = aws_db_subnet_group.staging.name
  vpc_security_group_ids = [local.bootstrap.rds_sg_id]
  availability_zone      = var.availability_zone
  multi_az               = false
  publicly_accessible    = false

  parameter_group_name = aws_db_parameter_group.staging.name

  # Fixed password from tfvars (kept in the team vault). Write-only: sent to AWS, never stored in state.
  # To change it: new value in tfvars + bump password_wo_version.
  # On restore the master user comes from the snapshot; the password is still set from tfvars.
  username            = var.master_username
  password_wo         = var.master_password
  password_wo_version = var.master_password_version

  backup_retention_period = var.backup_retention_days
  backup_window           = "16:48-17:18"         # UTC = 22:18-22:48 IST
  maintenance_window      = "sun:10:29-sun:10:59" # UTC = Sun 15:59-16:29 IST
  copy_tags_to_snapshot   = true

  auto_minor_version_upgrade = true
  engine_lifecycle_support   = "open-source-rds-extended-support-disabled"
  ca_cert_identifier         = "rds-ca-rsa2048-g1"

  deletion_protection       = true
  skip_final_snapshot       = false
  final_snapshot_identifier = "${var.identifier}-final"

  tags = {
    Name = var.identifier
  }

  # both only matter at create, and a diff on either forces a new (empty) DB:
  # clearing the snapshot later, or a snapshot whose master user isn't var.master_username
  lifecycle {
    ignore_changes = [snapshot_identifier, username]
  }
}
