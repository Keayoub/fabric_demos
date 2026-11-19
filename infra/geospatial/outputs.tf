output "workspace" {
  value = { id = module.workspace.id, url = module.workspace.url }
}

output "lakehouse" {
  value = { id = module.lakehouse.id, name = var.lakehouse_name, sql_endpoint = module.lakehouse.sql_endpoint }
}

output "notebook" {
  value = { id = fabric_notebook.canadian.id, name = var.notebook_name, folder_id = fabric_folder.engineering.id }
}

output "model" {
  value = var.publish_analytics ? { id = fabric_semantic_model.canadian[0].id, name = var.model_name } : null
}

output "report" {
  value = var.publish_analytics ? {
    id  = fabric_report.canadian[0].id
    url = "https://app.powerbi.com/groups/${module.workspace.id}/reports/${fabric_report.canadian[0].id}"
  } : null
}
