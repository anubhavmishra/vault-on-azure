provider "azurerm" {
}

resource "azurerm_resource_group" "default" {
  name     = "${var.resource_group_name}"
  location = "${var.location}"

  tags {
    environment = "dev"
  }
}

module "network" "vault-demo-network" {
  source              = "github.com/nicholasjackson/terraform-azurerm-network"
  location            = "${var.location}"
  resource_group_name = "${azurerm_resource_group.default.name}"
  subnet_prefixes     = "${var.subnet_prefixes}"
  subnet_names        = "${var.subnet_names}"
  vnet_name           = "tfaz-vnet"
  sg_name             = "${var.sg_name}"
}

resource "azurerm_public_ip" "vault-demo" {
  name                         = "vault-demo-public-ip"
  location                     = "${var.location}"
  resource_group_name          = "${azurerm_resource_group.default.name}"
  public_ip_address_allocation = "static"
  domain_name_label            = "${var.resource_group_name}-ssh"

  tags {
    environment = "dev"
  }
}

resource "azurerm_network_security_group" "vault-demo" {
  name                = "vault-demo-ssh-access"
  location            = "${var.location}"
  resource_group_name = "${azurerm_resource_group.default.name}"
}

resource "azurerm_network_security_rule" "ssh_access" {
  name                        = "ssh-access-rule"
  network_security_group_name = "${azurerm_network_security_group.vault-demo.name}"
  direction                   = "Inbound"
  access                      = "Allow"
  priority                    = 200
  source_address_prefix       = "*"
  source_port_range           = "*"
  destination_address_prefix  = "${azurerm_network_interface.vault-demo.private_ip_address}"
  destination_port_range      = "22"
  protocol                    = "TCP"
  resource_group_name         = "${azurerm_resource_group.default.name}"
}

resource "azurerm_network_security_rule" "ssh_access_vault_demo" {
  name                        = "allow-vault-demo-ssh"
  direction                   = "Inbound"
  access                      = "Allow"
  priority                    = 210
  source_address_prefix       = "*"
  source_port_range           = "*"
  destination_address_prefix  = "${azurerm_network_interface.vault-demo.private_ip_address}"
  destination_port_range      = "22"
  protocol                    = "Tcp"
  resource_group_name         = "${azurerm_resource_group.default.name}"
  network_security_group_name = "${module.network.security_group_name}"
}

resource "azurerm_network_interface" "vault-demo" {
  name                      = "vault-demo-nic"
  location                  = "${var.location}"
  resource_group_name       = "${azurerm_resource_group.default.name}"
  network_security_group_id = "${azurerm_network_security_group.vault-demo.id}"

  ip_configuration {
    name                          = "IPConfiguration"
    subnet_id                     = "${module.network.vnet_subnets[0]}"
    private_ip_address_allocation = "dynamic"
    public_ip_address_id          = "${azurerm_public_ip.vault-demo.id}"
  }

  tags {
    environment = "dev"
  }
}

resource "tls_private_key" "key" {
  algorithm   = "RSA"
}

resource "null_resource" "save-key" {
  triggers {
    key = "${tls_private_key.key.private_key_pem}"
  }

  provisioner "local-exec" {
    command = <<EOF
      mkdir -p ${path.module}/.ssh
      echo "${tls_private_key.key.private_key_pem}" > ${path.module}/.ssh/id_rsa
      chmod 0600 ${path.module}/.ssh/id_rsa
EOF
  }
}

resource "azurerm_virtual_machine" "vault-demo" {
  name                          = "vault-demo"
  location                      = "${var.location}"
  resource_group_name           = "${azurerm_resource_group.default.name}"
  network_interface_ids         = ["${azurerm_network_interface.vault-demo.id}"]
  vm_size                       = "Standard_DS1_v2"
  delete_os_disk_on_termination = true

  storage_image_reference {
    publisher = "Canonical"
    offer     = "UbuntuServer"
    sku       = "16.04-LTS"
    version   = "latest"
  }

  storage_os_disk {
    name              = "vault-demo-osdisk"
    caching           = "ReadWrite"
    create_option     = "FromImage"
    managed_disk_type = "Standard_LRS"
  }

  os_profile {
    computer_name  = "vault-demo"
    admin_username = "azureuser"
    admin_password = "Password1234!"
  }

  os_profile_linux_config {
    disable_password_authentication = true

    ssh_keys {
      path     = "/home/azureuser/.ssh/authorized_keys"
      key_data = "${trimspace(tls_private_key.key.public_key_openssh)} user@vaultdemo.io"
    }
  }

  identity = {
    type = "SystemAssigned"
  }

  tags {
    environment = "dev"
  }
}

resource "azurerm_virtual_machine_extension" "vault-demo" {
  name                  = "vault-demo-extension"
  location              = "${var.location}"
  resource_group_name   = "${azurerm_resource_group.default.name}"
  virtual_machine_name  = "${azurerm_virtual_machine.vault-demo.name}"
  publisher             = "Microsoft.OSTCExtensions"
  type                  = "CustomScriptForLinux"
  type_handler_version  = "1.2"

  settings             = <<SETTINGS
    {
      "commandToExecute": "${var.cmd_extension}",
       "fileUris": [
        "${var.cmd_script}"
       ]
    }
SETTINGS
}

# Gets the current subscription id
data "azurerm_subscription" "primary" {}

resource "azurerm_role_assignment" "vault-demo" {
  scope                = "${data.azurerm_subscription.primary.id}"
  role_definition_name = "Reader"
  principal_id         = "${lookup(azurerm_virtual_machine.vault-demo.identity[0], "principal_id")}"
}

