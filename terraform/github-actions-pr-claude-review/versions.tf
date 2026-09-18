terraform {
  required_version = ">= 1.9.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.60"
    }
  }

  # Local state: cr-tf-backend is accessed with sa-cr, which is not logged
  # in when applying this module with profile piq. tfstate is gitignored.
  backend "local" {
    path = "terraform.tfstate"
  }
}
