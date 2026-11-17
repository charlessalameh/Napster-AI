# These feed scripts/bootstrap-search.sh and the deploy workflow.

output "resource_group_name" {
  value = azurerm_resource_group.main.name
}

output "web_app_name" {
  value = azurerm_linux_web_app.main.name
}

output "web_app_url" {
  value = "https://${azurerm_linux_web_app.main.default_hostname}"
}

output "storage_account_name" {
  value = azurerm_storage_account.docs.name
}

output "docs_container_name" {
  value = azurerm_storage_container.docs.name
}

output "search_service_name" {
  value = azurerm_search_service.main.name
}

output "search_endpoint" {
  value = "https://${azurerm_search_service.main.name}.search.windows.net"
}

output "search_index_name" {
  value = var.search_index_name
}

output "openai_endpoint" {
  value = azurerm_cognitive_account.openai.endpoint
}

output "embedding_deployment_name" {
  value = azurerm_cognitive_deployment.embedding.name
}

output "embedding_model_name" {
  value = var.embedding_model_name
}

output "subscription_id" {
  value = var.subscription_id
}
