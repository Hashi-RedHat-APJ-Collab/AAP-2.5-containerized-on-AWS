terraform {
  required_providers {
    ansible = {
      version = "~> 1.3.0"
      source  = "ansible/ansible"
    }
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.98"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.1.0"
    }

  }
  required_version = ">= 1.11.0"
  # cloud {

  #   organization = "Hashi-RedHat-APJ-Collab"

  #   workspaces {
  #     name = "aap-25-containerized"
  #   }
  # }
}