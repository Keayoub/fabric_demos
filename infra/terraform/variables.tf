variable "prefix" {
  description = "Generic prefix for the general estate; choose a unique demo prefix."
  type        = string
  default     = "DEMO"
  validation {
    condition     = can(regex("^[A-Za-z][A-Za-z0-9-]{1,19}$", var.prefix))
    error_message = "Use 2-20 alphanumeric/hyphen characters, starting with a letter."
  }
}

variable "secure_prefix" {
  description = "Distinct naming boundary for the isolated estate."
  type        = string
  default     = "SEC"
  validation {
    condition     = can(regex("^[A-Za-z][A-Za-z0-9-]{1,19}$", var.secure_prefix)) && lower(var.secure_prefix) != lower(var.prefix)
    error_message = "Use a valid 2-20 character prefix distinct from the general prefix."
  }
}

variable "environments" {
  description = "Separate workspaces and data per environment; domains are shared governance containers."
  type        = set(string)
  default     = ["DEV"]
  validation {
    condition     = length(var.environments) > 0 && alltrue([for e in var.environments : can(regex("^[A-Z][A-Z0-9]{1,9}$", e))])
    error_message = "Supply at least one uppercase environment name, e.g. DEV, TEST, PROD."
  }
}

variable "capacity_name_general" {
  description = "Exact display name of an EXISTING, active Fabric capacity; never created or resized."
  type        = string
  default     = "F4 capacity name"
}

variable "capacity_name_secure" {
  description = "Existing isolated-area capacity name; null reuses general capacity. Separate capacity recommended."
  type        = string
  default     = null
  nullable    = true
}

variable "use_cli_auth" {
  description = "Use az login interactively; set false for environment-based service principal credentials."
  type        = bool
  default     = true
}

variable "domains" {
  description = "Generic governance hierarchy; secure MUST remain a separate root, not an enterprise subdomain."
  type = map(object({
    name   = string
    parent = optional(string)
    scope  = string
  }))
  default = {
    enterprise     = { name = "Enterprise", scope = "hub" }
    planning       = { name = "Planning and Development", parent = "enterprise", scope = "spoke" }
    planning_poc   = { name = "Permitting PoC", parent = "planning", scope = "spoke" }
    recreation     = { name = "Parks and Recreation", parent = "enterprise", scope = "spoke" }
    recreation_poc = { name = "Recreation PoC", parent = "recreation", scope = "spoke" }
    spatial        = { name = "Spatial", parent = "enterprise", scope = "spoke" }
    spatial_poc    = { name = "Spatial Staging PoC", parent = "spatial", scope = "spoke" }
    finance        = { name = "Finance", parent = "enterprise", scope = "spoke" }
    people         = { name = "Human Resources", parent = "enterprise", scope = "spoke" }
    secure         = { name = "Public Safety", scope = "secure" }
  }
  validation {
    condition = (
      try(var.domains["secure"].parent == null && var.domains["secure"].scope == "secure", false) &&
      alltrue([for k, d in var.domains :
        contains(["hub", "spoke", "secure"], d.scope) &&
        (k == "secure" || (d.scope != "secure" && d.parent != "secure")) &&
        length(d.name) + max(length(var.prefix), length(var.secure_prefix)) + 1 <= 40 &&
        (d.parent == null || (d.parent != k && contains(keys(var.domains), d.parent)))
      ])
    )
    error_message = "Domains need valid scopes/parents and <=40-character prefixed names; secure must be an isolated root."
  }
}

variable "workspaces" {
  description = "Workspace blueprints; keys are stable wiring identifiers, display names are configurable."
  type = map(object({
    area   = string
    layer  = optional(string)
    domain = string
    scope  = string
  }))
  default = {
    hub_ingestion = { area = "Hub", layer = "Ingestion", domain = "enterprise", scope = "hub_ingestion" }
    hub_curated   = { area = "Hub", layer = "Curated", domain = "enterprise", scope = "hub_curated" }
    planning      = { area = "Permitting", domain = "planning_poc", scope = "spoke" }
    spatial       = { area = "Spatial", domain = "spatial_poc", scope = "spoke" }
    recreation    = { area = "Recreation", domain = "recreation_poc", scope = "spoke" }
    secure        = { area = "Secure", domain = "secure", scope = "secure" }
  }
  validation {
    condition = (
      toset(keys(var.workspaces)) == toset(["hub_ingestion", "hub_curated", "planning", "spatial", "recreation", "secure"]) &&
      alltrue([for k, w in var.workspaces :
        can(regex("^[A-Za-z][A-Za-z0-9-]*$", w.area)) &&
        (w.layer == null ? true : can(regex("^[A-Za-z][A-Za-z0-9-]*$", w.layer))) &&
        contains(keys(var.domains), w.domain) &&
        (k == "secure" ? w.domain == "secure" && w.scope == "secure" : w.domain != "secure" && w.scope == (startswith(k, "hub_") ? k : "spoke"))
      ]) &&
      length(distinct([for k, w in var.workspaces : join("-", compact([k == "secure" ? var.secure_prefix : var.prefix, w.area, w.layer]))])) == length(var.workspaces)
    )
    error_message = "Keep the six wiring keys, unique valid names, matching scopes, and secure mapped only to its isolated domain."
  }
}

variable "group_role_map" {
  description = "ONE group-display-name map for workspace and domain roles; all security groups must already exist."
  type = map(object({
    boundary        = string
    workspace_roles = map(string)
    domain_roles    = optional(map(string), {})
  }))
  default = {
    "DEMO-Fabric-Admins" = {
      boundary = "general", workspace_roles = { hub_ingestion = "Admin", hub_curated = "Admin" }, domain_roles = { hub = "Admins" }
    }
    "DEMO-Fabric-Workspace-Admins" = {
      boundary = "general", workspace_roles = { spoke = "Admin" }, domain_roles = { spoke = "Admins" }
    }
    "DEMO-Fabric-Data-Engineers" = {
      boundary = "general", workspace_roles = { hub_ingestion = "Contributor", hub_curated = "Contributor", spoke = "Contributor" }, domain_roles = { hub = "Contributors", spoke = "Contributors" }
    }
    "DEMO-Fabric-BI-Developers" = {
      boundary = "general", workspace_roles = { spoke = "Contributor", hub_curated = "Viewer" }
    }
    "DEMO-Fabric-Viewers" = {
      boundary = "general", workspace_roles = { spoke = "Viewer" }
    }
    "SEC-Fabric-Admins" = {
      boundary = "secure", workspace_roles = { secure = "Admin" }, domain_roles = { secure = "Admins" }
    }
    "SEC-Fabric-Data-Engineers" = {
      boundary = "secure", workspace_roles = { secure = "Contributor" }, domain_roles = { secure = "Contributors" }
    }
    "SEC-Fabric-BI-Developers" = {
      boundary = "secure", workspace_roles = { secure = "Contributor" }
    }
    "SEC-Fabric-Viewers" = {
      boundary = "secure", workspace_roles = { secure = "Viewer" }
    }
  }
  validation {
    condition = length(var.group_role_map) > 0 && alltrue([for name, g in var.group_role_map :
      contains(["general", "secure"], g.boundary) &&
      alltrue([for s, r in g.workspace_roles :
        contains(g.boundary == "secure" ? ["secure"] : ["hub_ingestion", "hub_curated", "spoke"], s) &&
        contains(["Admin", "Member", "Contributor", "Viewer"], r)
      ]) &&
      alltrue([for s, r in g.domain_roles :
        contains(g.boundary == "secure" ? ["secure"] : ["hub", "spoke"], s) &&
        contains(["Admins", "Contributors"], r)
      ])
    ])
    error_message = "Use valid roles and never cross general/secure boundaries in either role map."
  }
  validation {
    condition     = anytrue([for g in values(var.group_role_map) : g.boundary == "secure" && try(g.workspace_roles["secure"] == "Admin", false)])
    error_message = "At least one isolated security group must administer the secure workspace."
  }
}

variable "item_names" {
  description = "All item display names; use identifier-safe names for lakehouses and warehouse."
  type        = map(string)
  default = {
    bronze        = "lh_bronze"
    silver        = "lh_silver"
    gold          = "lh_gold"
    warehouse     = "wh_gold"
    planning      = "lh_permitting"
    spatial       = "lh_spatial"
    history       = "nb_history_load"
    merge         = "nb_silver_merge"
    spatial_demo  = "nb_spatial_showcase"
    pipeline      = "pl_history_placeholder"
    spatial_model = "sm_spatial_showcase"
  }
  validation {
    condition = (
      toset(keys(var.item_names)) == toset(["bronze", "silver", "gold", "warehouse", "planning", "spatial", "history", "merge", "spatial_demo", "pipeline", "spatial_model"]) &&
      alltrue([for n in values(var.item_names) : can(regex("^[A-Za-z][A-Za-z0-9_]{0,99}$", n))]) &&
      var.item_names["history"] != var.item_names["merge"] &&
      var.item_names["bronze"] != var.item_names["silver"]
    )
    error_message = "Keep the item wiring keys and use identifier-safe names; items of the same workspace/type must have distinct names."
  }
}

variable "enable_shortcuts" {
  description = "Opt in only after publishing hub tables and reviewing source permissions."
  type        = bool
  default     = false
  validation {
    condition     = !var.enable_shortcuts || (var.shortcut_access_reviewed && sum([for tables in values(var.shortcut_tables) : length(tables)]) > 0)
    error_message = "Enabling shortcuts requires a nonempty table list and shortcut_access_reviewed=true."
  }
}

variable "shortcut_access_reviewed" {
  description = "Acknowledge source-table read-only grants for consumers; this is NOT an ACL or provider read-only switch."
  type        = bool
  default     = false
}

variable "shortcut_tables" {
  description = "Existing dbo hub gold tables needed per supported spoke; secure is deliberately ineligible."
  type        = map(set(string))
  default     = { planning = [], spatial = [] }
  validation {
    condition = alltrue([for spoke, tables in var.shortcut_tables :
      contains(["planning", "spatial"], spoke) &&
      alltrue([for t in tables : can(regex("^[A-Za-z][A-Za-z0-9_]*$", t))])
    ])
    error_message = "Only planning/spatial spokes and identifier-safe dbo table names are supported; no secure routes."
  }
}

variable "deploy_spatial_model" {
  description = "Second-stage opt in AFTER running the spatial notebook and waiting for SQL endpoint table discovery."
  type        = bool
  default     = false
}
