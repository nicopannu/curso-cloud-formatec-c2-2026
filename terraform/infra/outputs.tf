output "frontend_url" {
  value       = "http://${aws_instance.frontend.public_ip}"
  description = "URL pública del frontend (Banco Patacon)"
}

output "frontend_instance_id" {
  value       = aws_instance.frontend.id
  description = "Instance ID del frontend para filtrar métricas EC2"
}

output "backend_url" {
  value       = "http://${aws_instance.backend.public_ip}:8080"
  description = "URL pública del backend (API de transferencias)"
}

output "backend_health_url" {
  value       = "http://${aws_instance.backend.public_ip}:8080/health"
  description = "Health check del backend"
}

output "backend_instance_id" {
  value       = aws_instance.backend.id
  description = "Instance ID del backend para filtrar métricas EC2"
}
