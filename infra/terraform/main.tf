# Both capacities are looked up, never provisioned, resized or paused.
data "fabric_capacity" "general" {
  display_name = var.capacity_name_general
}

data "fabric_capacity" "secure" {
  display_name = coalesce(var.capacity_name_secure, var.capacity_name_general)
}

data "azuread_group" "security" {
  for_each         = var.group_role_map
  display_name     = each.key
  security_enabled = true
}

locals {
  root_domains = { for k, d in var.domains : k => d if d.parent == null }
  business_domains = {
    for k, d in var.domains : k => d
    if d.parent != null && contains(keys(local.root_domains), d.parent == null ? "" : d.parent)
  }
  poc_domains = {
    for k, d in var.domains : k => d
    if d.parent != null && contains(keys(local.business_domains), d.parent == null ? "" : d.parent)
  }
  domain_principals = {
    for k, d in var.domains : k => {
      for role in ["Admins", "Contributors"] : role => toset([
        for name, g in var.group_role_map : data.azuread_group.security[name].object_id
        if try(g.domain_roles[d.scope], "") == role
      ]) if anytrue([for g in values(var.group_role_map) : try(g.domain_roles[d.scope], "") == role])
    }
  }
  workspace_instances = merge([
    for env in var.environments : {
      for k, w in var.workspaces : "${env}/${k}" => merge(w, { environment = env, key = k })
    }
  ]...)
  lakehouse_blueprints = {
    bronze   = "hub_ingestion"
    silver   = "hub_ingestion"
    gold     = "hub_curated"
    planning = "planning"
    spatial  = "spatial"
  }
  lakehouse_instances = merge([
    for env in var.environments : {
      for k, workspace in local.lakehouse_blueprints : "${env}/${k}" => {
        environment = env, key = k, workspace_key = "${env}/${workspace}"
      }
    }
  ]...)
  workspace_roles = merge([
    for wk, w in local.workspace_instances : {
      for name, g in var.group_role_map : "${wk}/${name}" => {
        workspace_key = wk, group_name = name, role = g.workspace_roles[w.scope]
      } if contains(keys(g.workspace_roles), w.scope)
    }
  ]...)
  shortcut_instances = var.enable_shortcuts ? merge([
    for env in var.environments : merge([
      for spoke, tables in var.shortcut_tables : {
        for table in tables : "${env}/${spoke}/${table}" => {
          environment = env, spoke = spoke, table = table
        }
      }
    ]...)
  ]...) : {}
}

# Explicit hierarchy levels form an acyclic Terraform graph and keep security a root.
module "domain_root" {
  source          = "./modules/domain"
  for_each        = local.root_domains
  display_name    = "${each.key == "secure" ? var.secure_prefix : var.prefix}-${each.value.name}"
  role_principals = local.domain_principals[each.key]
}

module "domain_business" {
  source          = "./modules/domain"
  for_each        = local.business_domains
  display_name    = "${var.prefix}-${each.value.name}"
  parent_id       = module.domain_root[each.value.parent].id
  role_principals = local.domain_principals[each.key]
}

module "domain_poc" {
  source          = "./modules/domain"
  for_each        = local.poc_domains
  display_name    = "${var.prefix}-${each.value.name}"
  parent_id       = module.domain_business[each.value.parent].id
  role_principals = local.domain_principals[each.key]
}

locals {
  domain_ids = merge(
    { for k, d in module.domain_root : k => d.id },
    { for k, d in module.domain_business : k => d.id },
    { for k, d in module.domain_poc : k => d.id }
  )
}

module "workspace" {
  source       = "./modules/workspace"
  for_each     = local.workspace_instances
  display_name = join("-", compact([each.value.scope == "secure" ? var.secure_prefix : var.prefix, each.value.area, each.value.layer, each.value.environment]))
  capacity_id  = each.value.scope == "secure" ? data.fabric_capacity.secure.id : data.fabric_capacity.general.id
  description  = "${each.value.environment} ${each.value.scope} demo; synthetic data only."
}

# Aggregate assignments once per domain across environments to avoid drift.
resource "fabric_domain_workspace_assignments" "this" {
  for_each  = toset(distinct([for w in values(var.workspaces) : w.domain]))
  domain_id = local.domain_ids[each.key]
  workspace_ids = toset([
    for k, w in local.workspace_instances : module.workspace[k].id if w.domain == each.key
  ])
  lifecycle {
    precondition {
      condition     = length(local.domain_ids) == length(var.domains)
      error_message = "Domains must be an acyclic hierarchy with no more than three levels."
    }
  }
}

module "lakehouse" {
  source       = "./modules/lakehouse"
  for_each     = local.lakehouse_instances
  display_name = var.item_names[each.value.key]
  workspace_id = module.workspace[each.value.workspace_key].id
}

# A separate curated workspace lets BI developers read shared gold without editing it.
resource "fabric_warehouse" "gold" {
  for_each     = var.environments
  display_name = var.item_names["warehouse"]
  workspace_id = module.workspace["${each.key}/hub_curated"].id
}

module "role_assignment" {
  source       = "./modules/role_assignment"
  for_each     = local.workspace_roles
  workspace_id = module.workspace[each.value.workspace_key].id
  group_id     = data.azuread_group.security[each.value.group_name].object_id
  role         = each.value.role
}

# Only general-estate planning/spatial destinations can enter this graph.
module "shortcut" {
  source              = "./modules/shortcut"
  for_each            = local.shortcut_instances
  workspace_id        = module.workspace["${each.value.environment}/${each.value.spoke}"].id
  lakehouse_id        = module.lakehouse["${each.value.environment}/${each.value.spoke}"].id
  source_workspace_id = module.workspace["${each.value.environment}/hub_curated"].id
  source_lakehouse_id = module.lakehouse["${each.value.environment}/gold"].id
  table               = each.value.table
}

locals {
  notebook_instances = merge([
    for env in var.environments : {
      for kind, lakehouse in { history = "planning", merge = "planning", spatial_demo = "spatial" } : "${env}/${kind}" => {
        environment                    = env, kind = kind, lakehouse = lakehouse
      }
    }
  ]...)
  notebook_files = {
    history      = "nb_history_load.ipynb"
    merge        = "nb_silver_merge.ipynb"
    spatial_demo = "nb_spatial_showcase.ipynb"
  }
}

# Notebook bindings are tokenized with computed IDs rather than tenant-specific files.
resource "fabric_notebook" "sample" {
  for_each     = local.notebook_instances
  display_name = var.item_names[each.value.kind]
  workspace_id = module.workspace["${each.value.environment}/${each.value.lakehouse}"].id
  format       = "ipynb"
  definition = {
    "notebook-content.ipynb" = {
      source = "${path.module}/../../notebooks/${local.notebook_files[each.value.kind]}"
      tokens = {
        LAKEHOUSE_ID   = module.lakehouse["${each.value.environment}/${each.value.lakehouse}"].id
        LAKEHOUSE_NAME = var.item_names[each.value.lakehouse]
        WORKSPACE_ID   = module.workspace["${each.value.environment}/${each.value.lakehouse}"].id
      }
    }
  }
}

# An empty, unscheduled pipeline is intentionally harmless in a demo tenant.
resource "fabric_data_pipeline" "planning" {
  for_each     = var.environments
  display_name = var.item_names["pipeline"]
  workspace_id = module.workspace["${each.key}/planning"].id
  format       = "Default"
  definition = {
    "pipeline-content.json" = { source = "${path.module}/definitions/pipeline-content.json" }
  }
}

# Direct Lake creation is staged until the notebook has materialized its Delta tables.
resource "fabric_semantic_model" "spatial" {
  for_each     = var.deploy_spatial_model ? var.environments : toset([])
  display_name = var.item_names["spatial_model"]
  workspace_id = module.workspace["${each.key}/spatial"].id
  format       = "TMSL"
  definition = {
    "model.bim" = {
      source = "${path.module}/definitions/spatial-model.bim"
      tokens = {
        SQL_ENDPOINT = module.lakehouse["${each.key}/spatial"].sql_endpoint.connection_string
        DATABASE     = var.item_names["spatial"]
      }
    }
    "definition.pbism" = { source = "${path.module}/definitions/definition.pbism" }
  }
}
