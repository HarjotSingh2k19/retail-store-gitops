terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  backend "s3" {
    bucket = "gitops-factory-tfstate-446056240219"
    key    = "retail-store/terraform.tfstate"
    region = "ap-south-1"
  }
}
