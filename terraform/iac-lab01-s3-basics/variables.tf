variable "aws_region" {
  description = "Region AWS donde se creara el bucket de laboratorio."
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Nombre corto del proyecto usado para naming y tags."
  type        = string
  default     = "cloudcuyo-iac"

  validation {
    condition     = can(regex("^[a-z0-9-]{3,24}$", var.project_name))
    error_message = "project_name debe tener 3 a 24 caracteres: minusculas, numeros y guiones."
  }
}

variable "environment" {
  description = "Ambiente del recurso: dev, test, prod o lab."
  type        = string
  default     = "lab"

  validation {
    condition     = contains(["dev", "test", "prod", "lab"], var.environment)
    error_message = "environment debe ser dev, test, prod o lab."
  }
}

variable "owner" {
  description = "Responsable del recurso para trazabilidad y costos."
  type        = string
  default     = "formatec"
}
