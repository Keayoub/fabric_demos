variable "capacity_name" {
  description = "Exact name of an existing, active capacity; never created or resized."
  type        = string
}

variable "workspace_name" {
  type    = string
  default = "DEMO-Spatial-DEV"
}

variable "lakehouse_name" {
  type    = string
  default = "lh_spatial"
}

variable "notebook_name" {
  type    = string
  default = "nb_canadian_geo"
}

variable "notebook_folder_name" {
  type    = string
  default = "T02 - Engineering"
}

variable "model_name" {
  type    = string
  default = "sm_canadian_geo"
}

variable "report_name" {
  type    = string
  default = "rpt_canadian_geo"
}

variable "use_cli_auth" {
  type    = bool
  default = true
}

variable "publish_analytics" {
  description = "Enable only after the notebook has succeeded and SQL endpoint tables are visible."
  type        = bool
  default     = false
}

variable "spark_runtime_version" {
  description = "Pin the tested Fabric Spark runtime instead of inheriting a changing workspace default."
  type        = string
  default     = "1.3"
}

variable "spark_max_nodes" {
  description = "Starter-pool node/executor upper bound; size within the existing capacity limits."
  type        = number
  default     = 1
  validation {
    condition     = var.spark_max_nodes >= 1 && floor(var.spark_max_nodes) == var.spark_max_nodes
    error_message = "spark_max_nodes must be a positive integer."
  }
}
