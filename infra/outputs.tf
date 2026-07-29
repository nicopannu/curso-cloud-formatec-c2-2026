output "instance_id" {
  description = "ID de la instancia EC2 administrada por SSM."
  value       = aws_instance.web.id
}

output "public_ip" {
  description = "IP pública para comprobar HTTP."
  value       = aws_instance.web.public_ip
}

output "aws_region" {
  description = "Región efectiva del laboratorio."
  value       = local.effective_region
}

output "ansible_bucket" {
  description = "Bucket privado temporal usado por Ansible SSM."
  value       = aws_s3_bucket.ansible.bucket
}

output "student_identity" {
  description = "Identidad del alumno usada para nombres de recursos."
  value       = var.student_identity
}
