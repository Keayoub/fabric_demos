terraform {
  required_providers {
    fabric = { source = "microsoft/fabric" }
  }
}

variable "workspace_id" { type = string }
variable "group_id" { type = string }
variable "role" {
  type = string
  validation {
    condition     = contains(["Admin", "Member", "Contributor", "Viewer"], var.role)
    error_message = "Invalid Fabric workspace role."
  }
}

# Only existing Entra security groups are assigned, never individual demo users.
resource "fabric_workspace_role_assignment" "this" {
  workspace_id = var.workspace_id
  principal = {
    id   = var.group_id
    type = "Group"
  }
  role = var.role
}
