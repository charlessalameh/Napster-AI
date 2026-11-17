output "resource_group_name" {
  value = azurerm_resource_group.state.name
}

output "storage_account_name" {
  value = azurerm_storage_account.state.name
}

output "storage_account_id" {
  value = azurerm_storage_account.state.id
}

output "container_name" {
  value = azurerm_storage_container.state.name
}

# Paste these into the backend block of infra/providers.tf (or pass with -backend-config).
output "backend_config" {
  value = <<-EOT
    resource_group_name  = "${azurerm_resource_group.state.name}"
    storage_account_name = "${azurerm_storage_account.state.name}"
    container_name       = "${azurerm_storage_container.state.name}"
    key                  = "school-agent.tfstate"
    use_azuread_auth     = true
  EOT
}

output "easyauth_identity_id" {
  value = azurerm_user_assigned_identity.easyauth.id
}

output "easyauth_identity_client_id" {
  value = azurerm_user_assigned_identity.easyauth.client_id
}

output "easyauth_identity_principal_id" {
  value = azurerm_user_assigned_identity.easyauth.principal_id
}
