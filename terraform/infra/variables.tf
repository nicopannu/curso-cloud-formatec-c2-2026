variable "student_identity" {
  description = "Identificador del alumno (prefijo para recursos)"
  type        = string
  default     = "alumno"
}

variable "aws_region" {
  description = "Región AWS"
  type        = string
  default     = "us-east-1"
}
