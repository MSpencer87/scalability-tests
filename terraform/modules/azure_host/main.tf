resource "azurerm_network_interface" "nic" {
  name                = "${var.project_name}-${var.name}"
  resource_group_name = var.resource_group_name
  location            = var.location

  ip_configuration {
    name                          = "internal"
    subnet_id                     = var.subnet_id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = var.public_ip_address_id
  }
}

resource "azurerm_linux_virtual_machine" "main" {
  name                  = "${var.project_name}-${var.name}"
  resource_group_name   = var.resource_group_name
  location              = var.location
  size                  = var.size
  priority              = var.is_spot ? "Spot" : "Regular"
  admin_username        = var.ssh_user
  network_interface_ids = [azurerm_network_interface.nic.id]

  admin_ssh_key {
    username   = var.ssh_user
    public_key = file(var.ssh_public_key_path)
  }

  source_image_reference {
    publisher = var.os_image.publisher
    offer     = var.os_image.offer
    sku       = var.os_image.sku
    version   = var.os_image.version
  }

  os_disk {
    storage_account_type = "Standard_LRS"
    caching              = "ReadWrite"
  }
}

resource "null_resource" "host_configuration" {
  depends_on = [azurerm_linux_virtual_machine.main]

  connection {
    host = coalesce(azurerm_linux_virtual_machine.main.public_ip_address,
    azurerm_linux_virtual_machine.main.private_ip_address)
    private_key = file(var.ssh_private_key_path)
    user        = var.ssh_user

    bastion_host        = var.ssh_bastion_host
    bastion_user        = var.ssh_user
    bastion_private_key = file(var.ssh_private_key_path)
    timeout             = "120s"
  }

  provisioner "remote-exec" {
    inline = var.host_configuration_commands
  }
}

resource "local_file" "open_tunnels" {
  count = length(var.ssh_tunnels) > 0 ? 1 : 0
  content = templatefile("${path.module}/open-tunnels-to.sh", {
    ssh_bastion_host     = var.ssh_bastion_host,
    ssh_tunnels          = var.ssh_tunnels,
    private_name         = azurerm_linux_virtual_machine.main.private_ip_address,
    public_name          = azurerm_linux_virtual_machine.main.public_ip_address
    ssh_user             = var.ssh_user
    ssh_private_key_path = var.ssh_private_key_path
  })

  filename = "${path.module}/../../../config/open-tunnels-to-${var.name}.sh"
}

resource "null_resource" "open_tunnels" {
  count      = length(var.ssh_tunnels) > 0 ? 1 : 0
  depends_on = [null_resource.host_configuration]
  provisioner "local-exec" {
    interpreter = ["bash", "-c"]
    command     = local_file.open_tunnels[0].filename
  }
  triggers = {
    always_run = timestamp()
  }
}
