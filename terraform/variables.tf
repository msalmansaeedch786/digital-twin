variable "aws_region" {
  description = "AWS region for the infrastructure"
  type        = string
  default     = "eu-central-1"
}

variable "aws_profile" {
  description = "AWS CLI profile to use"
  type        = string
  default     = "digital-twin"
}

variable "project_name" {
  description = "Name of the project, used for naming and tagging all resources"
  type        = string
  default     = "digital-twin"
}
