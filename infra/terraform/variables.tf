variable "distros" {
  description = "Linux distributions to simulate the X-Road Security Server installation on. Images are systemd-enabled, built for Ansible/Molecule testing."
  type = map(object({
    image  = string
    family = string # debian | redhat
  }))
  default = {
    ubuntu2204 = { image = "geerlingguy/docker-ubuntu2204-ansible:latest", family = "debian" }
    ubuntu2404 = { image = "geerlingguy/docker-ubuntu2404-ansible:latest", family = "debian" }
    rocky8     = { image = "geerlingguy/docker-rockylinux8-ansible:latest", family = "redhat" }
    rocky9     = { image = "geerlingguy/docker-rockylinux9-ansible:latest", family = "redhat" }
  }
}

variable "name_prefix" {
  description = "Prefix for simulated container names."
  type        = string
  default     = "xroad-sim"
}
