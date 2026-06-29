output "containers" {
  description = "Simulated distro nodes and their container names."
  value       = { for k, c in docker_container.node : k => c.name }
}

output "inventory_path" {
  description = "Ansible inventory generated for the simulated matrix."
  value       = local_file.inventory.filename
}

output "next_step" {
  value = "Run: cd ../ansible && ansible-playbook -i inventory.ini site.yml"
}
