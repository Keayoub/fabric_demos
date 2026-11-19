terraform {
  required_providers {
    fabric = { source = "microsoft/fabric" }
  }
}

variable "display_name" { type = string }
variable "capacity_id" { type = string }
variable "description" { type = string }

# Existing capacity lookup keeps billing infrastructure outside the demo lifecycle.
resource "fabric_workspace" "this" {
  display_name = var.display_name
  description  = var.description
  capacity_id  = var.capacity_id
}

output "id" { value = fabric_workspace.this.id }
output "url" { value = "https://app.fabric.microsoft.com/groups/${fabric_workspace.this.id}/list" }
