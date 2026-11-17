# One-time bootstrap: resource group + storage account that holds the Terraform state
# of the main stack. Run locally once (after `az login`); its own state stays local
# and is git-ignored. See README "Getting started".

terraform {
  required_version = ">= 1.6"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

provider "azurerm" {
  features {}
  subscription_id = var.subscription_id
  # Talk to Blob Storage with Entra ID instead of storage keys.
  storage_use_azuread = true
}

data "azurerm_client_config" "current" {}

# Storage account names are global, lowercase, 3-24 chars: add a short random suffix.
resource "random_string" "suffix" {
  length  = 5
  upper   = false
  special = false
}

resource "azurerm_resource_group" "state" {
  name     = "${var.name_prefix}-tfstate-rg"
  location = var.location
  tags     = var.tags
}

resource "azurerm_storage_account" "state" {
  name                     = "${var.name_prefix}tf${random_string.suffix.result}"
  resource_group_name      = azurerm_resource_group.state.name
  location                 = azurerm_resource_group.state.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  min_tls_version          = "TLS1_2"

  # No account keys: access is Entra ID + RBAC only.
  shared_access_key_enabled       = false
  allow_nested_items_to_be_public = false

  blob_properties {
    versioning_enabled = true # lets you roll back a bad state file
  }

  tags = var.tags
}

resource "azurerm_storage_container" "state" {
  name                  = "tfstate"
  storage_account_id    = azurerm_storage_account.state.id
  container_access_type = "private"

  # Needs the role below before the data plane accepts us.
  depends_on = [azurerm_role_assignment.me_blob]
}

# Lets the person running this bootstrap create the container and use the state.
resource "azurerm_role_assignment" "me_blob" {
  scope                = azurerm_storage_account.state.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = data.azurerm_client_config.current.object_id
}
