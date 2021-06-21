terraform {
 required_version = ">= 0.13"
  required_providers {
    libvirt = {
      source  = "dmacvicar/libvirt"
     version = "0.6.3"
    }
  } 
}


################################################################################
# PROVIDERS
################################################################################


provider "libvirt" {
  uri = "qemu:///system"
}

#provider "libvirt" {
#  alias = "server2"
#  uri   = "qemu+ssh://root@192.168.100.10/system"
#}


################################################################################
# ENV VARS
################################################################################

#variable "hostname" { default = "host" }
#variable "domain" { default = "test.local" }
#variable "memoryMB" { default = 1024*1 }
#variable "cpu" { default = 1 }


# https://www.terraform.io/docs/commands/environment-variables.html

variable "VM_COUNT" {
  default = 1
  type = number
}

variable "VM_USER" {
  default = "ubuntu"
  type = string
}

variable "VM_HOSTNAME" {
  default = "vm"
  type = string
}

variable "VM_IMG_URL" {
  default = "https://cloud-images.ubuntu.com/releases/focal/release-20210603/ubuntu-20.04-server-cloudimg-amd64.img"
  type = string
}

variable "VM_IMG_FORMAT" {
  default = "qcow2"
  type = string
}

# https://www.ipaddressguide.com/cidr
variable "VM_CIDR_RANGE" {
  default = "10.10.10.0/24"
  type = string
}

#variable "LIBVIRT_POOL" {
#  default = "default"
#  type = string
#}




################################################################################
# DATA TEMPLATES
################################################################################

# https://www.terraform.io/docs/providers/template/d/file.html

# https://www.terraform.io/docs/providers/template/d/cloudinit_config.html
data "template_file" "user_data" {
  template = file("${path.module}/cloud_init.cfg")
  vars = {
    VM_USER = var.VM_USER
  }
}

data "template_file" "network_config" {
  template = file("${path.module}/network_config.cfg")
}



################################################################################
# RESOURCES
################################################################################

#resource "libvirt_pool" "default" {
#  name = "${var.VM_HOSTNAME}_pool"
#  type = "dir"
#  path = abspath("${var.LIBVIRT_POOL}")
#}


# We fetch the disk image for the operating system from the given url.
resource "libvirt_volume" "vm_disk_image" {
  name   = "${var.VM_HOSTNAME}_disk_image.${var.VM_IMG_FORMAT}"
  #pool   = libvirt_pool.default.name
  pool   = "default"
  source = var.VM_IMG_URL
  format = var.VM_IMG_FORMAT
}


# resource "libvirt_volume" "vm_master" {
#   name   = "master_${var.VM_HOSTNAME}.${var.VM_IMG_FORMAT}"
#   base_volume_id = libvirt_volume.vm_disk_image.id
#   pool   = libvirt_volume.vm_disk_image.pool
# }


resource "libvirt_volume" "vm_worker" {
  count  = var.VM_COUNT
  name   = "worker_${var.VM_HOSTNAME}-${count.index + 1}.${var.VM_IMG_FORMAT}"
  base_volume_id = libvirt_volume.vm_disk_image.id
  pool   = "default"
}


# Create a public network for the VMs
# https://www.ipaddressguide.com/cidrv

#resource "libvirt_network" "vm_public_network" {
#   name = "${var.VM_HOSTNAME}_network"
#   autostart = true
#   mode = "nat"
#   domain = "${var.VM_HOSTNAME}.local"

   # TODO: FIX CIDR ADDRESSES RANGE?
   # With `wait_for_lease` enabled, we get an error in the end of the VMs
   #  creation:
   #   - 'Requested operation is not valid: the address family of a host entry IP must match the address family of the dhcp element's parent'
   # But the VMs will be running and accessible via ssh.

#   addresses = ["${var.VM_CIDR_RANGE}"]

#   dhcp {
#    enabled = true
#   }
#   dns {
#    enabled = true
#   }
#}




# for more info about paramater check this out
# https://github.com/dmacvicar/terraform-provider-libvirt/blob/master/website/docs/r/cloudinit.html.markdown
# Use CloudInit to add our ssh-key to the instance
# you can add also meta_data field
resource "libvirt_cloudinit_disk" "cloudinit" {
  name           = "${var.VM_HOSTNAME}_cloudinit.iso"
  user_data      = data.template_file.user_data.rendered
  network_config = data.template_file.network_config.rendered
  #pool           = libvirt_pool.default.name
  pool           = "default" 
}

# Create the machine
resource "libvirt_domain" "vm" {
  count  = var.VM_COUNT
  name   = "${var.VM_HOSTNAME}-${count.index + 1}"
  memory = "1024"
  vcpu   = 1
  autostart = true

  # TODO: FIX qemu-ga?
  # qemu-ga needs to be installed and working inside the VM, and currently is
  #  not working. Maybe it needs some configuration.
  qemu_agent = true

  cloudinit = "${libvirt_cloudinit_disk.cloudinit.id}"

  #//address = [cidrhost(libvirt_network.vm_public_network.addresses, count.index + 1)]

  network_interface {
    #hostname = "${var.VM_HOSTNAME}-${count.index + 1}"
    #network_id = "${libvirt_network.vm_public_network1.id}"
    network_name = "default"

    #addresses = ["${cidrhost(libvirt_network.vm_public_network.addresses, count.index + 1)}"]
    #addresses = ["${cidrhost(var.VM_CIDR_RANGE, count.index + 1)}"]

    # TODO: Fix wait for lease?
    # qemu-ga must be running inside the VM. See notes above in `qemu_agent`.
    #wait_for_lease = true
  }

  # IMPORTANT
  # Ubuntu can hang is a isa-serial is not present at boot time.
  # If you find your CPU 100% and never is available this is why.
  #
  # This is a known bug on cloud images, since they expect a console
  # we need to pass it:
  # https://bugs.launchpad.net/cloud-images/+bug/1573095
  console {
    type        = "pty"
    target_port = "0"
    target_type = "serial"
  }

  console {
    type        = "pty"
    target_type = "virtio"
    target_port = "1"
  }

  disk {
    volume_id = "${libvirt_volume.vm_worker[count.index].id}"
  }

  graphics {
    type        = "spice"
    listen_type = "address"
    autoport    = true
  }
}
