variable "aws_profile" {
  description = "AWS CLI profile pointing at the staging account (both regions are in the same account)"
  type        = string
}

variable "aws_account_id" {
  description = "Staging AWS account ID (providers refuse to run against any other)"
  type        = string
}

variable "prefect_port" {
  description = "Prefect server API port on the Mumbai staging EC2 (prefect-external-service.yaml / EndpointSlice)"
  type        = number
  default     = 4200
}
