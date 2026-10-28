terraform {
  required_version = ">= 1.10"

  # State lives in HCP Terraform (Lab 7, Part 1 Step 6). Put your organization's
  # name here; the workspace is the one environment this folder describes.
  cloud {
    organization = "ooad-spry"

    workspaces {
      name = "spry-dev"
    }
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.7"
    }
  }
}

provider "aws" {
  region = var.region

  # Lab 4's rule: PROJECT_NAME on everything that takes tags, written once.
  default_tags {
    tags = {
      PROJECT_NAME = var.project_name
      ManagedBy    = "terraform"
    }
  }
}

data "aws_caller_identity" "current" {}
