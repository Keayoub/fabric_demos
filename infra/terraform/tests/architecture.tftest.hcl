# All runs are PLAN-only mocks: no tenant access, item creation or apply operations.
mock_provider "fabric" {
  mock_data "fabric_capacity" {
    defaults = {
      id    = "00000000-0000-4000-8000-000000000001"
      state = "Active"
    }
  }
  mock_resource "fabric_workspace" {
    defaults = {
      id = "00000000-0000-4000-8000-000000000002"
    }
  }
  mock_resource "fabric_domain" {
    defaults = {
      id = "00000000-0000-4000-8000-000000000003"
    }
  }
  mock_resource "fabric_lakehouse" {
    defaults = {
      id = "00000000-0000-4000-8000-000000000004"
      properties = {
        sql_endpoint_properties = {
          id                  = "00000000-0000-4000-8000-000000000005"
          connection_string   = "mock.datawarehouse.fabric.microsoft.com"
          provisioning_status = "Success"
        }
      }
    }
  }
}

mock_provider "azuread" {
  mock_data "azuread_group" {
    defaults = {
      object_id = "00000000-0000-4000-8000-000000000006"
    }
  }
}

run "default_estate" {
  command = plan

  assert {
    condition     = length(module.workspace) == 6 && length(module.lakehouse) == 5 && length(fabric_warehouse.gold) == 1
    error_message = "Default DEV must have six workspaces, five lakehouses and one warehouse."
  }
  assert {
    condition     = length(module.role_assignment) == 21 && length(fabric_notebook.sample) == 3 && length(fabric_data_pipeline.planning) == 1
    error_message = "Workspace access and harmless notebook/pipeline placeholders must be complete."
  }
  assert {
    condition     = length(module.shortcut) == 0 && length(fabric_semantic_model.spatial) == 0
    error_message = "Shortcuts and table-dependent semantic models must be opt-in."
  }
  assert {
    condition     = contains(keys(module.domain_root), "secure") && !contains(keys(module.domain_business), "secure") && length(local.domain_ids) == 10
    error_message = "Secure governance must be a separate root in the ten-domain hierarchy."
  }
  assert {
    condition = alltrue([
      for r in values(local.workspace_roles) :
      startswith(r.workspace_key, "DEV/secure") == (var.group_role_map[r.group_name].boundary == "secure")
    ])
    error_message = "Every general/secure workspace role must remain inside its boundary."
  }
}

run "multiple_environments_and_staged_features" {
  command = plan
  variables {
    environments             = ["DEV", "TEST"]
    enable_shortcuts         = true
    shortcut_access_reviewed = true
    shortcut_tables          = { planning = ["dim_date"], spatial = ["dim_date"] }
    deploy_spatial_model     = true
    capacity_name_secure     = "isolated-demo-capacity"
  }

  assert {
    condition     = length(module.workspace) == 12 && length(module.lakehouse) == 10 && length(module.role_assignment) == 42
    error_message = "Adding an environment must replicate all workspace/data/access boundaries."
  }
  assert {
    condition     = length(module.shortcut) == 4 && length(fabric_semantic_model.spatial) == 2 && length(local.domain_ids) == 10
    error_message = "Staged features scale per environment without duplicating domains."
  }
  assert {
    condition     = alltrue([for s in values(local.shortcut_instances) : contains(["planning", "spatial"], s.spoke)])
    error_message = "No shortcut can involve the isolated estate."
  }
}

run "reject_cross_boundary_grants" {
  command = plan
  variables {
    group_role_map = {
      "General-Fabric-Admins"  = { boundary = "general", workspace_roles = { secure = "Admin" } }
      "Isolated-Fabric-Admins" = { boundary = "secure", workspace_roles = { secure = "Admin" } }
    }
  }
  expect_failures = [var.group_role_map]
}

run "reject_secure_shortcuts" {
  command = plan
  variables {
    shortcut_tables = { secure = ["dim_date"] }
  }
  expect_failures = [var.shortcut_tables]
}

run "reject_unreviewed_shortcuts" {
  command = plan
  variables {
    enable_shortcuts = true
    shortcut_tables  = { planning = ["dim_date"] }
  }
  expect_failures = [var.enable_shortcuts]
}
