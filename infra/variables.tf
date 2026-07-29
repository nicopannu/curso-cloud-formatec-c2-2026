variable "aws_region" {
  description = "Región AWS del laboratorio. En GitHub Actions se toma desde AWS_REGION."
  type        = string
  default     = null
}

variable "student_identity" {
  description = "Identidad del alumno para nombres de recursos: minúsculas, dígitos y guion."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{1,30}[a-z0-9]$", var.student_identity))
    error_message = "student_identity debe usar sólo minúsculas, dígitos y guion, empezar y terminar con alfanumérico, y tener 3 a 32 caracteres."
  }
}
