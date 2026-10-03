terraform {
  # Pinned to the minor, not a floor. ">= 1.5.0" let a brew upgrade put this
  # laptop on 1.16.4 while CI stayed on 1.5.0 for months — and a local apply
  # would have stamped the state with a version CI could no longer read.
  # Patches are allowed; a minor bump is a deliberate change to
  # .terraform-version, which CI reads too.
  required_version = "~> 1.16.0"

  required_providers {
    aws = {
      source = "hashicorp/aws"
      # 5.100.0 was the final 5.x release — that line receives no further
      # fixes, new services or security patches. Checked against the v6
      # upgrade guide: none of its breaking changes touch this stack (no
      # aws_s3_bucket.region references, no REST API Gateway v1 resources
      # — this uses apigatewayv2 — no Elastic Inference, no RDS
      # character_set_name).
      version = "~> 6.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.0"
    }
  }

  backend "s3" {
    bucket         = "digital-twin-terraform-state-231740"
    key            = "infrastructure/terraform.tfstate"
    region         = "eu-central-1"
    dynamodb_table = "digital-twin-terraform-locks"
    encrypt        = true
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = var.project_name
      ManagedBy   = "terraform"
      Environment = "production"
    }
  }
}
