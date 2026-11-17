data "azurerm_client_config" "current" {}

# Short random suffix so global names (storage, OpenAI subdomain, web app) never collide,
# including after destroy -> deploy.
resource "random_string" "suffix" {
  length  = 5
  upper   = false
  special = false
}

locals {
  base = "${var.name_prefix}-${random_string.suffix.result}"
}

resource "azurerm_resource_group" "main" {
  name     = "${var.name_prefix}-rg"
  location = var.location
  tags     = var.tags
}

# ---------------------------------------------------------------- Monitoring

resource "azurerm_log_analytics_workspace" "main" {
  name                = "${local.base}-law"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  sku                 = "PerGB2018"
  retention_in_days   = 30
  tags                = var.tags
}

resource "azurerm_application_insights" "main" {
  name                = "${local.base}-appi"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  workspace_id        = azurerm_log_analytics_workspace.main.id
  application_type    = "web"
  tags                = var.tags
}

# ------------------------------------------------------------------- Storage
# Holds the school documents. No account keys: Entra ID + RBAC only.

resource "azurerm_storage_account" "docs" {
  name                            = "${var.name_prefix}st${random_string.suffix.result}"
  resource_group_name             = azurerm_resource_group.main.name
  location                        = azurerm_resource_group.main.location
  account_tier                    = "Standard"
  account_replication_type        = "LRS"
  min_tls_version                 = "TLS1_2"
  shared_access_key_enabled       = false
  allow_nested_items_to_be_public = false
  tags                            = var.tags
}

resource "azurerm_storage_container" "docs" {
  name                  = var.docs_container_name
  storage_account_id    = azurerm_storage_account.docs.id
  container_access_type = "private"

  depends_on = [azurerm_role_assignment.deployer_blob]
}

# ------------------------------------------------------------- Azure OpenAI

resource "azurerm_cognitive_account" "openai" {
  name                  = "${local.base}-aoai"
  location              = azurerm_resource_group.main.location
  resource_group_name   = azurerm_resource_group.main.name
  kind                  = "OpenAI"
  sku_name              = "S0"
  custom_subdomain_name = local.base # required for Entra ID (token) auth
  local_auth_enabled    = false      # keys disabled: Managed Identity only
  tags                  = var.tags
}

resource "azurerm_cognitive_deployment" "chat" {
  name                 = var.chat_deployment_name
  cognitive_account_id = azurerm_cognitive_account.openai.id

  model {
    format  = "OpenAI"
    name    = var.chat_model_name
    version = var.chat_model_version
  }

  sku {
    name     = var.model_sku
    capacity = var.chat_capacity
  }
}

resource "azurerm_cognitive_deployment" "embedding" {
  name                 = var.embedding_deployment_name
  cognitive_account_id = azurerm_cognitive_account.openai.id

  model {
    format  = "OpenAI"
    name    = var.embedding_model_name
    version = var.embedding_model_version
  }

  sku {
    name     = var.model_sku
    capacity = var.embedding_capacity
  }

  # Deployments on one account are created one at a time; avoids 409 conflicts.
  depends_on = [azurerm_cognitive_deployment.chat]
}

# ---------------------------------------------------------------- AI Search

resource "azurerm_search_service" "main" {
  name                = "${local.base}-search"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  sku                 = var.search_sku

  # Entra ID only: no admin/query keys.
  local_authentication_enabled = false

  # The indexer reads blobs and calls OpenAI as this identity.
  identity {
    type = "SystemAssigned"
  }

  tags = var.tags
}

# --------------------------------------------------------------- App Service

resource "azurerm_service_plan" "main" {
  name                = "${local.base}-plan"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  os_type             = "Linux"
  sku_name            = var.app_service_sku
  tags                = var.tags
}

resource "azurerm_linux_web_app" "main" {
  name                = "${local.base}-web"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  service_plan_id     = azurerm_service_plan.main.id
  https_only          = true
  tags                = var.tags

  identity {
    type = "SystemAssigned"
  }

  site_config {
    always_on           = true
    minimum_tls_version = "1.2"
    ftps_state          = "Disabled"
    http2_enabled       = true
    health_check_path   = "/health"

    health_check_eviction_time_in_min = 5
    app_command_line                  = "gunicorn --bind=0.0.0.0 --timeout 120 app:app"

    application_stack {
      python_version = "3.12"
    }
  }

  # Endpoints and names only. No keys anywhere.
  app_settings = {
    SCM_DO_BUILD_DURING_DEPLOYMENT        = "true"
    AZURE_OPENAI_ENDPOINT                 = azurerm_cognitive_account.openai.endpoint
    AZURE_OPENAI_CHAT_DEPLOYMENT          = azurerm_cognitive_deployment.chat.name
    AZURE_OPENAI_EMBEDDING_DEPLOYMENT     = azurerm_cognitive_deployment.embedding.name
    AZURE_SEARCH_ENDPOINT                 = "https://${azurerm_search_service.main.name}.search.windows.net"
    AZURE_SEARCH_INDEX                    = var.search_index_name
    APPLICATIONINSIGHTS_CONNECTION_STRING = azurerm_application_insights.main.connection_string
  }
}

# --------------------------------------------------------------------- RBAC
# Managed Identity + RBAC only. See README for the table.

# Web app -> OpenAI (generate answers, embed the question)
resource "azurerm_role_assignment" "web_openai" {
  scope                = azurerm_cognitive_account.openai.id
  role_definition_name = "Cognitive Services OpenAI User"
  principal_id         = azurerm_linux_web_app.main.identity[0].principal_id
}

# Web app -> Search (query the index)
resource "azurerm_role_assignment" "web_search" {
  scope                = azurerm_search_service.main.id
  role_definition_name = "Search Index Data Reader"
  principal_id         = azurerm_linux_web_app.main.identity[0].principal_id
}

# Search service -> Storage (indexer reads the documents)
resource "azurerm_role_assignment" "search_blob" {
  scope                = azurerm_storage_account.docs.id
  role_definition_name = "Storage Blob Data Reader"
  principal_id         = azurerm_search_service.main.identity[0].principal_id
}

# Search service -> OpenAI (embedding skill + integrated vectorizer)
resource "azurerm_role_assignment" "search_openai" {
  scope                = azurerm_cognitive_account.openai.id
  role_definition_name = "Cognitive Services OpenAI User"
  principal_id         = azurerm_search_service.main.identity[0].principal_id
}

# Deployer (you locally, or the GitHub Actions identity) -> what the bootstrap step needs:
# upload documents, and create the index/data source/skillset/indexer via the Search REST API.
resource "azurerm_role_assignment" "deployer_blob" {
  scope                = azurerm_storage_account.docs.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = data.azurerm_client_config.current.object_id
}

resource "azurerm_role_assignment" "deployer_search_service" {
  scope                = azurerm_search_service.main.id
  role_definition_name = "Search Service Contributor"
  principal_id         = data.azurerm_client_config.current.object_id
}

resource "azurerm_role_assignment" "deployer_search_data" {
  scope                = azurerm_search_service.main.id
  role_definition_name = "Search Index Data Contributor"
  principal_id         = data.azurerm_client_config.current.object_id
}
