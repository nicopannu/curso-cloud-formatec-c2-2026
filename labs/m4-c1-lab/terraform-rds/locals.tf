locals {
  student_slug = substr(replace(lower(var.student_identity), "/[^a-z0-9-]/", "-"), 0, 24)
  name_prefix  = "m4-c1-${local.student_slug}"

  common_tags = {
    StudentIdentity = var.student_identity
    Lab             = "m4-c1-rds"
    ManagedBy       = "terraform"
  }

  backend_b_names = toset([
    "backend-b-01",
    "backend-b-02",
  ])
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = local.common_tags
  }
}

data "aws_caller_identity" "current" {}

data "aws_vpc" "foundation" {
  filter {
    name   = "tag:Name"
    values = ["${local.name_prefix}-vpc"]
  }
}

data "aws_subnets" "db" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.foundation.id]
  }

  filter {
    name   = "tag:Tier"
    values = ["db"]
  }
}

data "aws_security_group" "backend" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.foundation.id]
  }

  filter {
    name   = "tag:Name"
    values = ["${local.name_prefix}-backend-sg"]
  }
}

data "aws_instances" "backend_b" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.foundation.id]
  }

  filter {
    name   = "tag:Role"
    values = ["backend-b"]
  }

  filter {
    name   = "instance-state-name"
    values = ["running"]
  }
}

data "aws_network_interfaces" "backend_b" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.foundation.id]
  }

  filter {
    name   = "attachment.instance-id"
    values = data.aws_instances.backend_b.ids
  }
}

data "aws_iam_role" "backend_b" {
  for_each = local.backend_b_names
  name     = "${local.name_prefix}-${each.key}-role"
}
