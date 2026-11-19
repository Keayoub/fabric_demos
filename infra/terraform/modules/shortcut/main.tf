terraform {
  required_providers {
    fabric = { source = "microsoft/fabric" }
  }
}

variable "workspace_id" { type = string }
variable "lakehouse_id" { type = string }
variable "source_workspace_id" { type = string }
variable "source_lakehouse_id" { type = string }
variable "table" { type = string }

# An internal shortcut inherits effective permissions; it has no read_only flag.
resource "fabric_shortcut" "this" {
  workspace_id = var.workspace_id
  item_id      = var.lakehouse_id
  name         = var.table
  path         = "Tables/dbo"
  target = {
    onelake = {
      workspace_id = var.source_workspace_id
      item_id      = var.source_lakehouse_id
      path         = "Tables/dbo/${var.table}"
    }
  }
}
