variable "aws_region" {
  description = "Región AWS del laboratorio."
  type        = string
  default     = "us-east-1"
}

variable "project" {
  description = "Nombre corto del proyecto."
  type        = string
  default     = "cloudcuyo"
}

variable "environment" {
  description = "Ambiente del laboratorio."
  type        = string
  default     = "lab"
}

variable "student_identity" {
  description = "Identidad en minúsculas, sin espacios, para nombres y tags."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.student_identity))
    error_message = "student_identity sólo puede contener minúsculas, números y guiones."
  }
}

variable "student_cidr" {
  description = "IP pública del alumno en formato CIDR /32."
  type        = string

  validation {
    condition     = can(cidrhost(var.student_cidr, 0)) && endswith(var.student_cidr, "/32")
    error_message = "student_cidr debe ser una dirección IPv4 válida terminada en /32."
  }
}

variable "control_public_key_path" {
  description = "Ruta local a la clave pública notebook -> control node."
  type        = string
}

variable "managed_public_key_path" {
  description = "Ruta local a la clave pública control node -> managed nodes."
  type        = string
}

variable "instance_type" {
  description = "Tipo de instancia para los nodos del laboratorio."
  type        = string
  default     = "t3.micro"
}

variable "vpc_cidr" {
  description = "CIDR de la VPC."
  type        = string
  default     = "10.30.0.0/16"
}

variable "public_subnet_cidr" {
  description = "CIDR de la subnet pública."
  type        = string
  default     = "10.30.10.0/24"
}
