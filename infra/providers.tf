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

  # Remote state in the storage account created by infra/bootstrap-state.
  # Values are passed at init time (see README and deploy.yml):
  #   terraform init -backend-config=backend.hcl
  backend "azurerm" {
    key              = "school-agent.tfstate"
    use_azuread_auth = true
  }
}

provider "azurerm" {
  features {
    cognitive_account {
      # Deleted Azure OpenAI accounts are soft-deleted and block re-use of the name
      # and quota. Purge on destroy so destroy -> deploy works cleanly.
      purge_soft_delete_on_destroy = true
    }
    resource_group {
      # Allow destroy even if something (e.g. a portal-created item) is left inside.
      prevent_deletion_if_contains_resources = false
    }
  }
  subscription_id     = var.subscription_id
  storage_use_azuread = true
}
