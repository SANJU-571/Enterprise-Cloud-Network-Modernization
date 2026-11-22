terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.40"
    }
  }

  # Remote state - bucket/table are bootstrapped once with scripts/bootstrap_state.sh
  backend "s3" {
    bucket         = "stratos-tfstate-prod"
    key            = "prod/terraform.tfstate"
    region         = "ca-central-1"
    dynamodb_table = "stratos-tf-locks"
    encrypt        = true
  }
}

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project   = "enterprise-cloud-network-modernization"
      ManagedBy = "terraform"
    }
  }
}

provider "aws" {
  alias  = "dr"
  region = var.dr_region

  default_tags {
    tags = {
      Project   = "enterprise-cloud-network-modernization"
      ManagedBy = "terraform"
    }
  }
}
