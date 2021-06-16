terraform {
 required_version = ">= 0.13"
  required_providers {
    libvirt = {
      source  = "dmacvicar/libvirt"
     version = "0.6.3"
    }
  } 
}

variable "hostname" { default = "host" }
variable "domain" { default = "test.local" }
variable "memoryMB" { default = 1024*1 }
variable "cpu" { default = 1 }

provider "libvirt" {
  uri = "qemu:///system"
}

#provider "libvirt" {
#  alias = "server2"
#  uri   = "qemu+ssh://root@192.168.100.10/system"
#}


#resource "libvirt_volume" "ubuntu2004" {
#  name = "ubuntu-20.04-server-cloudimg-amd64-1.img"
#  pool = "pool-1"
#  source = "/home/Downloads/ubuntu-20.04-server-cloudimg-amd64-1.img"
       
#  format = "raw"
#}

resource "libvirt_volume" "os_image" {
  name = "${var.hostname}-os_image"
  pool = "default"
  source = "https://cloud-images.ubuntu.com/focal/current/focal-server-cloudimg-amd64.img"
  format = "qcow2"
}


# Define KVM domain to create
resource "libvirt_domain" "ubuntu-20-stable" {
  name   = "ubunut-20-stable"
  memory = "1024"
  vcpu   = 1

  network_interface {
    network_name = "default"
  }

  disk {
    volume_id = "${libvirt_volume.os_image.id}"
  }

  console {
    type = "pty"
    target_type = "serial"
    target_port = "0"
  }

  graphics {
    type = "spice"
    listen_type = "address"
    autoport = true
  }
}
