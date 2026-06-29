terraform {
  required_version = ">= 1.5"
  required_providers {
    docker = {
      source  = "kreuzwerker/docker"
      version = "~> 3.0"
    }
  }
}

provider "docker" {}

resource "docker_image" "distro" {
  for_each = var.distros
  name     = each.value.image
}

# Systemd-enabled containers acting as throwaway VMs, one per distribution.
# privileged + cgroup mount is what lets systemd (and thus the X-Road services) run.
resource "docker_container" "node" {
  for_each = var.distros

  name       = "${var.name_prefix}-${each.key}"
  image      = docker_image.distro[each.key].image_id
  privileged = true
  rm         = false
  must_run   = true

  # Keep systemd happy.
  tmpfs = {
    "/run"     = ""
    "/run/lock" = ""
  }

  volumes {
    host_path      = "/sys/fs/cgroup"
    container_path = "/sys/fs/cgroup"
    read_only      = false
  }

  # The geerlingguy images already start systemd as PID 1; no command override needed.
}

# Hand the running matrix to Ansible. Connection is via the Docker plugin, so no SSH is required.
resource "local_file" "inventory" {
  filename = "${path.module}/../ansible/inventory.ini"
  content = templatefile("${path.module}/inventory.tftpl", {
    debian_hosts = [for k, v in var.distros : { name = k, container = "${var.name_prefix}-${k}" } if v.family == "debian"]
    redhat_hosts = [for k, v in var.distros : { name = k, container = "${var.name_prefix}-${k}" } if v.family == "redhat"]
  })
  depends_on = [docker_container.node]
}
