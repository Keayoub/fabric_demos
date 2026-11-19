output "workspaces" {
  description = "Workspace IDs and browser URLs keyed by ENV/blueprint."
  value = {
    for k, w in module.workspace : k => { id = w.id, url = w.url }
  }
}

output "domains" {
  value = local.domain_ids
}

output "lakehouses" {
  value = {
    for k, lh in module.lakehouse : k => {
      id = lh.id, sql_endpoint = lh.sql_endpoint
    }
  }
}

output "directory_bootstrap" {
  description = "Input to the optional OneLake REST helper; only the general permitting spoke."
  value = {
    for env in var.environments : env => {
      workspace_id = module.workspace["${env}/planning"].id
      lakehouse_id = module.lakehouse["${env}/planning"].id
      directories  = ["Files/bronze", "Files/bronze/permits", "Files/bronze/permits/history", "Files/bronze/permits/api"]
    }
  }
}

output "semantic_models" {
  value = { for env, model in fabric_semantic_model.spatial : env => model.id }
}
