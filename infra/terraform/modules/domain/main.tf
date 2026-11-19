terraform {
  required_providers {
    fabric = { source = "microsoft/fabric" }
  }
}

variable "display_name" { type = string }
variable "parent_id" {
  type    = string
  default = null
}
variable "role_principals" {
  type    = map(set(string))
  default = {}
}

# Domains are governance containers, not a substitute for workspace or data ACLs.
resource "fabric_domain" "this" {
  display_name     = var.display_name
  parent_domain_id = var.parent_id
}

# One assignment set per domain/role avoids competing authoritative writers.
resource "fabric_domain_role_assignments" "this" {
  for_each   = var.role_principals
  domain_id  = fabric_domain.this.id
  role       = each.key
  principals = [for id in each.value : { id = id, type = "Group" }]
}

output "id" { value = fabric_domain.this.id }
