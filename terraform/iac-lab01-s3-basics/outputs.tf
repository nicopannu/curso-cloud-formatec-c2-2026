output "bucket_name" {
  description = "Nombre final del bucket creado por Terraform."
  value       = aws_s3_bucket.lab.bucket
}

output "bucket_arn" {
  description = "ARN del bucket creado."
  value       = aws_s3_bucket.lab.arn
}

output "aws_region" {
  description = "Region configurada para el provider AWS."
  value       = var.aws_region
}

output "tags" {
  description = "Tags comunes aplicados por default_tags del provider."
  value       = local.common_tags
}
