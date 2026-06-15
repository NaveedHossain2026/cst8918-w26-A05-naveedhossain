# Configure the Terraform runtime requirements.
terraform {
  required_version = ">= 1.1.0"

  required_providers {
    # Azure Resource Manager provider and version
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0.2"
    }
    cloudinit = {
      source  = "hashicorp/cloudinit"
      version = "2.3.3"
    }
  }
}

# Define providers and their config params
provider "azurerm" {
  # Leave the features block empty to accept all defaults
  features {}
}

provider "cloudinit" {
  # Configuration options
}

# =====================================================================
# 4.1 VARIABLES
# =====================================================================
variable "labelPrefix" {
  type        = string
  description = "Your college username. This will form the beginning of various resource names."
}

variable "region" {
  type        = string
  default     = "canadacentral"
  description = "The Azure region where resources will be deployed."
}

variable "admin_username" {
  type        = string
  default     = "azureadmin"
  description = "The admin username for the Ubuntu VM."
}

# =====================================================================
# 4.2 RESOURCE GROUP
# =====================================================================
resource "azurerm_resource_group" "rg" {
  name     = "${var.labelPrefix}-A05-RG"
  location = var.region
}

# =====================================================================
# 4.3 PUBLIC IP ADDRESS (Updated to Standard SKU)
# =====================================================================
resource "azurerm_public_ip" "pip" {
  name                = "${var.labelPrefix}-pip"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  allocation_method   = "Static"
  sku                 = "Standard"
}

# =====================================================================
# 4.4 VIRTUAL NETWORK
# =====================================================================
resource "azurerm_virtual_network" "vnet" {
  name                = "${var.labelPrefix}-vnet"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  address_space       = ["10.0.0.0/16"]
}

# =====================================================================
# 4.5 SUBNET
# =====================================================================
resource "azurerm_subnet" "subnet" {
  name                 = "${var.labelPrefix}-subnet"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.0.1.0/24"]
}

# =====================================================================
# 4.6 SECURITY GROUP (SSH & HTTP rules inlined)
# =====================================================================
resource "azurerm_network_security_group" "nsg" {
  name                = "${var.labelPrefix}-nsg"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  security_rule {
    name                       = "SSH"
    priority                   = 1001
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "HTTP"
    priority                   = 1002
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

# =====================================================================
# 4.7 VIRTUAL NETWORK INTERFACE CARD (NIC)
# =====================================================================
resource "azurerm_network_interface" "nic" {
  name                = "${var.labelPrefix}-nic"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.subnet.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.pip.id
  }
}

# =====================================================================
# 4.8 APPLY THE SECURITY GROUP TO THE VM NIC (Option 2)
# =====================================================================
resource "azurerm_network_interface_security_group_association" "nic_nsg" {
  network_interface_id      = azurerm_network_interface.nic.id
  network_security_group_id = azurerm_network_security_group.nsg.id
}

# =====================================================================
# 4.9 INIT SCRIPT DATA SOURCE
# =====================================================================
data "cloudinit_config" "config" {
  gzip          = false
  base64_encode = true

  part {
    content_type = "text/x-shellscript"
    content      = file("${path.module}/init.sh")
  }
}

# =====================================================================
# 4.10 VIRTUAL MACHINE (Adjusted for East US 2 Capacity constraints)
# =====================================================================
resource "azurerm_linux_virtual_machine" "vm" {
  name                = "${var.labelPrefix}-webserver"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  size                = "Standard_D2s_v3"  
  admin_username      = var.admin_username

  network_interface_ids = [
    azurerm_network_interface.nic.id,
  ]

  admin_ssh_key {
    username   = var.admin_username
    public_key = file("${pathexpand("~/.ssh/id_rsa.pub")}") 
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts"
    version   = "latest"
  }

  custom_data = data.cloudinit_config.config.rendered
}

# =====================================================================
# OUTPUT VALUES
# =====================================================================
output "resource_group_name" {
  value       = azurerm_resource_group.rg.name
  description = "The name of the created resource group."
}

output "public_ip_address" {
  value       = azurerm_linux_virtual_machine.vm.public_ip_address
  description = "The public IP address of the web server."
}
