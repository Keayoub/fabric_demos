terraform {
  required_version = ">= 1.9, < 2.0"
  required_providers {
    fabric = {
      source  = "microsoft/fabric"
      version = "= 1.15.0"
    }
    azuread = {
      source  = "hashicorp/azuread"
      version = "~> 3.0"
    }
  }
}

# Domain workspace assignment is a documented preview resource in this release.
provider "fabric" {
  preview = true
  use_cli = var.use_cli_auth
}

# Both providers resolve interactive credentials from the same Azure CLI session.
provider "azuread" {
  use_cli = var.use_cli_auth
}
