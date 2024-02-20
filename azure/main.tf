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

data "azurerm_resource_group" "resource_group" {
  name = "fiap-tech-challenge-main-group"
}


resource "azurerm_network_security_group" "security_group" {
  name                = "fiap-tech-challenge-main-security-group"
  location            = data.azurerm_resource_group.resource_group.location
  resource_group_name = data.azurerm_resource_group.resource_group.name


  tags = {
    environment = data.azurerm_resource_group.resource_group.tags["environment"]
  }
}

resource "azurerm_virtual_network" "main_network" {
  name                = "fiap-tech-challenge-main-network"
  location            = data.azurerm_resource_group.resource_group.location
  resource_group_name = data.azurerm_resource_group.resource_group.name
  address_space       = ["10.0.0.0/16"]
  dns_servers         = ["10.0.0.4", "10.0.0.5"]

  subnet {
    name           = "default-subnet"
    address_prefix = "10.0.1.0/24"
  }

  subnet {
    name           = "api-gateway-subnet"
    address_prefix = "10.0.2.0/24"
    security_group = azurerm_network_security_group.security_group.id
  }

  tags = {
    environment = data.azurerm_resource_group.resource_group.tags["environment"]
  }
}

data "azurerm_subnet" "api_gateway_subnet" {
  virtual_network_name = azurerm_virtual_network.main_network.name
  resource_group_name  = data.azurerm_resource_group.resource_group.name
  name                 = "api-gateway-subnet"
}

resource "azurerm_api_management" "api_management" {
  name                = "fiap-tech-challenge-main-api-management"
  location            = data.azurerm_resource_group.resource_group.location
  resource_group_name = data.azurerm_resource_group.resource_group.name
  publisher_name      = "FIAP Tech Challenge"
  publisher_email     = "this.programmer@ooutlook.com"

  sku_name = "Developer_1"
}