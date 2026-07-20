variable "name" {
  type = string
}

variable "ami_id" {
  type = string
}

variable "instance_type" {
  type = string
}

variable "subnet_id" {
  type = string
}

variable "security_group_ids" {
  type = list(string)
}

variable "key_name" {
  type = string
}

variable "user_data" {
  type    = string
  default = null
}

variable "associate_public_ip" {
  type    = bool
  default = true
}

variable "additional_tags" {
  type    = map(string)
  default = {}
}
