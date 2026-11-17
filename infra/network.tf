# Optional hardening (enable_private_networking = true): the web app reaches Azure OpenAI,
# AI Search and Blob Storage through Private Endpoints inside a VNet, so that traffic never
# crosses the public internet.
#
# Not locked down on purpose: the services keep their public endpoint (still Entra ID + RBAC
# only, keys are off) because the deploy pipeline needs it. GitHub runners upload the
# documents and call the Search REST API, and Search's indexer reads storage and calls
# OpenAI over the public path unless you add shared private links (higher Search tier).
# See README "Hardening".

locals {
  private_networking = var.enable_private_networking ? 1 : 0

  # Private DNS zone per service so the normal host names resolve to the private IPs.
  private_dns_zones = var.enable_private_networking ? toset([
    "privatelink.openai.azure.com",
    "privatelink.cognitiveservices.azure.com",
    "privatelink.search.windows.net",
    "privatelink.blob.core.windows.net",
  ]) : toset([])

  private_endpoints = var.enable_private_networking ? {
    openai = {
      resource_id = azurerm_cognitive_account.openai.id
      subresource = "account"
      zones       = ["privatelink.openai.azure.com", "privatelink.cognitiveservices.azure.com"]
    }
    search = {
      resource_id = azurerm_search_service.main.id
      subresource = "searchService"
      zones       = ["privatelink.search.windows.net"]
    }
    blob = {
      resource_id = azurerm_storage_account.docs.id
      subresource = "blob"
      zones       = ["privatelink.blob.core.windows.net"]
    }
  } : {}
}

resource "azurerm_virtual_network" "main" {
  count               = local.private_networking
  name                = "${local.base}-vnet"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  address_space       = [var.vnet_cidr]
  tags                = var.tags
}

# The web app's outbound traffic leaves through this subnet (VNet integration).
resource "azurerm_subnet" "integration" {
  count                = local.private_networking
  name                 = "app-integration"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main[0].name
  address_prefixes     = [cidrsubnet(var.vnet_cidr, 8, 1)]

  delegation {
    name = "appservice"
    service_delegation {
      name    = "Microsoft.Web/serverFarms"
      actions = ["Microsoft.Network/virtualNetworks/subnets/action"]
    }
  }
}

# The private endpoints live here.
resource "azurerm_subnet" "private_endpoints" {
  count                = local.private_networking
  name                 = "private-endpoints"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main[0].name
  address_prefixes     = [cidrsubnet(var.vnet_cidr, 8, 2)]
}

resource "azurerm_private_dns_zone" "zone" {
  for_each            = local.private_dns_zones
  name                = each.key
  resource_group_name = azurerm_resource_group.main.name
  tags                = var.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "link" {
  for_each              = local.private_dns_zones
  name                  = "link-${replace(each.key, ".", "-")}"
  resource_group_name   = azurerm_resource_group.main.name
  private_dns_zone_name = azurerm_private_dns_zone.zone[each.key].name
  virtual_network_id    = azurerm_virtual_network.main[0].id
  tags                  = var.tags
}

resource "azurerm_private_endpoint" "pe" {
  for_each            = local.private_endpoints
  name                = "${local.base}-${each.key}-pe"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  subnet_id           = azurerm_subnet.private_endpoints[0].id
  tags                = var.tags

  private_service_connection {
    name                           = "${each.key}-connection"
    private_connection_resource_id = each.value.resource_id
    subresource_names              = [each.value.subresource]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "default"
    private_dns_zone_ids = [for z in each.value.zones : azurerm_private_dns_zone.zone[z].id]
  }

  depends_on = [azurerm_private_dns_zone_virtual_network_link.link]
}
