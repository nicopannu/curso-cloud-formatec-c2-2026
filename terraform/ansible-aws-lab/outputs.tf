output "ansible_control_public_ip" {
  description = "IP pública para acceder al control node."
  value       = module.ansible_control.public_ip
}

output "ansible_control_instance_id" {
  description = "ID del control node."
  value       = module.ansible_control.instance_id
}

output "managed_private_ips" {
  description = "IPs privadas usadas por el inventario Ansible."
  value = {
    web01 = module.web01.private_ip
    web02 = module.web02.private_ip
  }
}

output "managed_public_ips" {
  description = "IPs públicas para validar HTTP desde student_cidr."
  value = {
    web01 = module.web01.public_ip
    web02 = module.web02.public_ip
  }
}

output "ssh_control_command" {
  description = "Ejemplo de acceso. Ajustar la ruta de la clave privada si fuera necesario."
  value       = "ssh -i ~/.ssh/formatec-control ubuntu@${module.ansible_control.public_ip}"
}
