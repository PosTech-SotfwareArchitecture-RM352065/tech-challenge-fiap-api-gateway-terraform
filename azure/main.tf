terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "3.90.0"
    }
  }
  backend "azurerm" {
    key = "terraform-api-gateway.tfstate"
  }
}

provider "azurerm" {
  features {}
}

data "azurerm_resource_group" "main_group" {
  name = "fiap-tech-challenge-main-group"
}

data "azurerm_virtual_network" "virtual_network" {
  name                = "fiap-tech-challenge-network"
  resource_group_name = data.azurerm_resource_group.main_group.name
}

data "azurerm_subnet" "api_gateway_subnet" {
  name                 = "fiap-tech-challenge-gateway-subnet"
  resource_group_name  = data.azurerm_virtual_network.virtual_network.resource_group_name
  virtual_network_name = data.azurerm_virtual_network.virtual_network.name
}

data "azurerm_public_ip" "public_ip" {
  name                = "fiap-tech-challenge-public-ip"
  resource_group_name = data.azurerm_resource_group.main_group.name
}

# since these variables are re-used - a locals block makes this more maintainable
locals {
  frontend_port_name             = "fiap-tech-challenge-application-gateway-public-ip-port"
  frontend_ip_configuration_name = "fiap-tech-challenge-application-gateway-public-ip-config"
  listener_name                  = "fiap-tech-challenge-application-gateway-public-ip-http-listener"
  request_routing_rule_name      = "fiap-tech-challenge-application-gateway-services-routing-rule"

  api_backend_address_pool_name = "fiap-tech-challenge-application-gateway-api-backend-pool"
  api_http_setting_name         = "fiap-tech-challenge-application-gateway-api-http-settings"

  auth_backend_address_pool_name = "fiap-tech-challenge-application-gateway-auth-backend-pool"
  auth_http_setting_name         = "fiap-tech-challenge-application-gateway-auth-http-settings"
}

resource "azurerm_application_gateway" "app_gateway" {
  name                = "fiap-tech-challenge-application-gateway"
  resource_group_name = data.azurerm_resource_group.main_group.name
  location            = data.azurerm_resource_group.main_group.location

  sku {
    name     = "Standard_v2"
    tier     = "Standard_v2"
    capacity = 2
  }

  gateway_ip_configuration {
    name      = "fiap-gateway-ip-configuration"
    subnet_id = data.azurerm_subnet.api_gateway_subnet.id
  }

  frontend_port {
    name = local.frontend_port_name
    port = 80
  }

  frontend_ip_configuration {
    name                 = local.frontend_ip_configuration_name
    public_ip_address_id = data.azurerm_public_ip.public_ip.id
  }

  backend_address_pool {
    name  = local.api_backend_address_pool_name
    fqdns = ["172.210.124.176"]
  }

  backend_address_pool {
    name  = local.auth_backend_address_pool_name
    fqdns = ["sanduba-auth-function.azurewebsites.net"]
  }

  backend_http_settings {
    name                                = local.auth_http_setting_name
    cookie_based_affinity               = "Disabled"
    path                                = "/api/auth"
    port                                = 443
    protocol                            = "Https"
    request_timeout                     = 60
    pick_host_name_from_backend_address = true
  }

  backend_http_settings {
    name                                = local.api_http_setting_name
    cookie_based_affinity               = "Disabled"
    path                                = ""
    port                                = 9000
    protocol                            = "Http"
    request_timeout                     = 60
    pick_host_name_from_backend_address = true
    probe_name                          = "api-health-probe"
  }

  http_listener {
    name                           = local.listener_name
    frontend_ip_configuration_name = local.frontend_ip_configuration_name
    frontend_port_name             = local.frontend_port_name
    protocol                       = "Http"
  }

  request_routing_rule {
    name                       = local.request_routing_rule_name
    priority                   = 1
    rule_type                  = "PathBasedRouting"
    http_listener_name         = local.listener_name
    backend_address_pool_name  = null
    backend_http_settings_name = null
    url_path_map_name          = "fiap-tech-challenge-gateway-route-paths"
  }

  probe {
    name                                      = "api-health-probe"
    protocol                                  = "Http"
    pick_host_name_from_backend_http_settings = true
    path                                      = "/health"
    interval                                  = 30
    timeout                                   = 30
    unhealthy_threshold                       = 3
  }

  url_path_map {
    name                               = "fiap-tech-challenge-gateway-route-paths"
    default_backend_address_pool_name  = local.auth_backend_address_pool_name
    default_backend_http_settings_name = local.auth_http_setting_name
    path_rule {
      name                       = "auth-service"
      paths                      = ["/auth"]
      backend_address_pool_name  = local.auth_backend_address_pool_name
      backend_http_settings_name = local.auth_http_setting_name
    }
    path_rule {
      name                       = "customer-service"
      paths                      = ["/cliente"]
      backend_address_pool_name  = local.api_backend_address_pool_name
      backend_http_settings_name = local.api_http_setting_name
    }
    path_rule {
      name                       = "order-service"
      paths                      = ["/pedido"]
      backend_address_pool_name  = local.api_backend_address_pool_name
      backend_http_settings_name = local.api_http_setting_name
    }
    path_rule {
      name                       = "cart-service"
      paths                      = ["/carrinho"]
      backend_address_pool_name  = local.api_backend_address_pool_name
      backend_http_settings_name = local.api_http_setting_name
    }
    path_rule {
      name                       = "menu-service"
      paths                      = ["/cardapio"]
      backend_address_pool_name  = local.api_backend_address_pool_name
      backend_http_settings_name = local.api_http_setting_name
    }

  }

  tags = {
    environment = data.azurerm_resource_group.main_group.tags["environment"]
  }
}

data "azurerm_storage_account" "log_storage_account" {
  name                = "sandubalog"
  resource_group_name = "fiap-tech-challenge-observability-group"
}

data "azurerm_log_analytics_workspace" "log_workspace" {
  name                = "fiap-tech-challenge-observability-workspace"
  resource_group_name = "fiap-tech-challenge-observability-group"
}

resource "azurerm_monitor_diagnostic_setting" "application_gateway_monitor" {
  name                       = "fiap-tech-challenge-application-gateway-monitor"
  target_resource_id         = azurerm_application_gateway.app_gateway.id
  storage_account_id         = data.azurerm_storage_account.log_storage_account.id
  log_analytics_workspace_id = data.azurerm_log_analytics_workspace.log_workspace.id

  enabled_log {
    category = "ApplicationGatewayAccessLog"
  }

  enabled_log {
    category = "ApplicationGatewayPerformanceLog"
  }

  enabled_log {
    category = "ApplicationGatewayFirewallLog"
  }

  metric {
    category = "AllMetrics"
  }
}