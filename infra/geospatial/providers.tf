terraform {
  required_version = ">= 1.9, < 2.0"
  required_providers {
    fabric = {
      source  = "microsoft/fabric"
      version = "= 1.15.0"
    }
  }
}

# Workspace item folders are a documented preview feature in this provider.
provider "fabric" {
  preview = true
  use_cli = var.use_cli_auth
}
