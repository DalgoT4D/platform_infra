########################################
# ECR pull-through cache for Docker Hub
########################################

# Nodes pull Docker Hub images (Airbyte platform + connectors, temporal, ...) via
# <account>.dkr.ecr.<region>.amazonaws.com/docker-hub/<owner>/<image>:<tag>.
# First pull: ECR fetches from Docker Hub on AWS's side and caches; later pulls come from ECR.
# Layers are served from S3, so with the S3 gateway endpoint (network.tf) they skip the NAT.
# Used by: global.image.registry in airbyte/helm/values*.yaml.
# Node role needs ecr:CreateRepository + ecr:BatchImportUpstreamImage: cluster/terraform/cluster.tf.

# Docker Hub username + access token, created by hand in the console (keeps the token out of state):
#   Secrets Manager > Other type of secret > keys "username" and "accessToken"
#   name: ecr-pullthroughcache/docker-hub (the "ecr-pullthroughcache/" prefix is required by ECR)
data "aws_secretsmanager_secret" "docker_hub" {
  name = var.ecr_docker_hub_secret_name
}

resource "aws_ecr_pull_through_cache_rule" "docker_hub" {
  ecr_repository_prefix = var.ecr_docker_hub_prefix
  upstream_registry_url = "registry-1.docker.io" # Docker Hub's registry endpoint (docker.io is an alias)
  credential_arn        = data.aws_secretsmanager_secret.docker_hub.arn
}

# Settings for the repos ECR creates on first pull.
resource "aws_ecr_repository_creation_template" "docker_hub" {
  prefix               = var.ecr_docker_hub_prefix
  description          = "Repos auto-created by the Docker Hub pull-through cache"
  applied_for          = ["PULL_THROUGH_CACHE"]
  image_tag_mutability = "MUTABLE" # cache must follow upstream tags

  encryption_configuration {
    encryption_type = "AES256"
  }

  lifecycle_policy = jsonencode({
    rules = [
      # A re-pushed tag leaves the old build without a tag; nothing pulls it again.
      {
        rulePriority = 1
        description  = "Drop untagged images after 7 days"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = 7
        }
        action = { type = "expire" }
      },
      # By age, not count: several versions of one connector can be in use at once.
      # An in-use image is re-fetched from Docker Hub at most once per period (AWS side, not NAT).
      {
        rulePriority = 2
        description  = "Drop images cached more than ${var.ecr_cache_max_age_days} days ago"
        selection = {
          tagStatus   = "any"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = var.ecr_cache_max_age_days
        }
        action = { type = "expire" }
      },
    ]
  })
}
