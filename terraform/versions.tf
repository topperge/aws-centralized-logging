terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source = "hashicorp/aws"
      # >= 6.0 is required for the per-resource `region` argument used to
      # create CloudWatch Logs destinations in every spoke region.
      version = ">= 6.0"
    }
    random = {
      source  = "hashicorp/random"
      version = ">= 3.5"
    }
  }
}

provider "aws" {
  region = var.region

  default_tags {
    tags = merge({ Solution = local.solution_id }, var.tags)
  }
}
