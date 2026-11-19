terraform {
  required_providers {
    fabric = { source = "microsoft/fabric" }
  }
}

variable "display_name" { type = string }
variable "workspace_id" { type = string }

# Schema-enabled lakehouses use dbo consistently in notebooks, models and shortcuts.
resource "fabric_lakehouse" "this" {
  display_name = var.display_name
  workspace_id = var.workspace_id
  configuration = {
    enable_schemas = true
  }
}

output "id" { value = fabric_lakehouse.this.id }
output "sql_endpoint" { value = fabric_lakehouse.this.properties.sql_endpoint_properties }
