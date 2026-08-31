variable "aws_region" {
  description = "Region where the M4-C1 foundation was deployed."
  type        = string
  default     = "us-east-1"
}

variable "student_identity" {
  description = "Same identity used by the foundation stack."
  type        = string

  validation {
    condition     = length(trimspace(var.student_identity)) > 0
    error_message = "student_identity must not be empty."
  }
}
