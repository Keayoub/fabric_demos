# This standalone state intentionally does not deploy the full municipal mesh.
data "fabric_capacity" "existing" {
  display_name = var.capacity_name
}

module "workspace" {
  source       = "../terraform/modules/workspace"
  display_name = var.workspace_name
  capacity_id  = data.fabric_capacity.existing.id
  description  = "Canadian municipal open-data geospatial demonstration; no sensitive data."
}

module "lakehouse" {
  source       = "../terraform/modules/lakehouse"
  display_name = var.lakehouse_name
  workspace_id = module.workspace.id
}

# A single starter node keeps this bounded example suitable for existing small capacities.
resource "fabric_spark_workspace_settings" "demo" {
  workspace_id = module.workspace.id
  environment = {
    runtime_version = var.spark_runtime_version
  }
  pool = {
    starter_pool = {
      max_node_count = var.spark_max_nodes
      max_executors  = var.spark_max_nodes
    }
  }
  job = {
    conservative_job_admission_enabled = false
    session_timeout_in_minutes         = 5
  }
}

# Folders are scoped to this new workspace, never to the existing training workspace.
resource "fabric_folder" "engineering" {
  display_name = var.notebook_folder_name
  workspace_id = module.workspace.id
}

resource "fabric_notebook" "canadian" {
  depends_on   = [fabric_spark_workspace_settings.demo]
  display_name = var.notebook_name
  workspace_id = module.workspace.id
  folder_id    = fabric_folder.engineering.id
  format       = "ipynb"
  definition = {
    "notebook-content.ipynb" = {
      source = "${path.module}/../../notebooks/nb_canadian_geo.ipynb"
      tokens = {
        LAKEHOUSE_ID   = module.lakehouse.id
        LAKEHOUSE_NAME = var.lakehouse_name
        WORKSPACE_ID   = module.workspace.id
      }
    }
  }
}

# Direct Lake reads the real Delta tables rather than embedding a synthetic snapshot.
resource "fabric_semantic_model" "canadian" {
  count        = var.publish_analytics ? 1 : 0
  display_name = var.model_name
  workspace_id = module.workspace.id
  format       = "TMSL"
  definition = {
    "model.bim" = {
      source = "${path.module}/definitions/model.bim"
      tokens = {
        SQL_ENDPOINT = module.lakehouse.sql_endpoint.connection_string
        DATABASE     = var.lakehouse_name
      }
    }
    "definition.pbism" = {
      source = "${path.module}/definitions/definition.pbism"
    }
  }
}

# PBIR is the supported report definition format; no private visual API is used.
resource "fabric_report" "canadian" {
  count        = var.publish_analytics ? 1 : 0
  display_name = var.report_name
  workspace_id = module.workspace.id
  format       = "PBIR"
  definition = {
    for part in fileset("${path.module}/report", "**") : part => {
      source = "${path.module}/report/${part}"
      tokens = { SEMANTIC_MODEL_ID = fabric_semantic_model.canadian[0].id }
    }
  }
}
