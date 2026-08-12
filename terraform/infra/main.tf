# ─── Banco Patacon — Infraestructura para monitoreo ───
# M3-C5 LAB01: despliega frontend + backend con CloudWatch agent

terraform {
  required_version = ">= 1.5"

  # El workflow completa bucket/key/region durante terraform init.
  backend "s3" {}

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# ─── Data sources ───

data "aws_ssm_parameter" "al2023_ami" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-6.1-x86_64"
}

data "aws_vpc" "default" {
  default = true
}

# ─── IAM ───

resource "aws_iam_role" "ec2_cloudwatch" {
  name = "${var.student_identity}-ec2-cw-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "cloudwatch_agent" {
  role       = aws_iam_role.ec2_cloudwatch.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

resource "aws_iam_instance_profile" "ec2_cloudwatch" {
  name = "${var.student_identity}-ec2-cw-profile"
  role = aws_iam_role.ec2_cloudwatch.name
}

# ─── Security Groups ───

resource "aws_security_group" "frontend" {
  name        = "${var.student_identity}-frontend-sg"
  description = "HTTP frontend"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "HTTP"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.student_identity}-frontend-sg" }
}

resource "aws_security_group" "backend" {
  name        = "${var.student_identity}-backend-sg"
  description = "HTTP backend"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "HTTP API"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.student_identity}-backend-sg" }
}

# ─── EC2 — Frontend (nginx) ───

resource "aws_instance" "frontend" {
  ami                         = data.aws_ssm_parameter.al2023_ami.value
  instance_type               = "t3.micro"
  associate_public_ip_address = true
  iam_instance_profile        = aws_iam_instance_profile.ec2_cloudwatch.name
  vpc_security_group_ids      = [aws_security_group.frontend.id]
  user_data                   = file("${path.module}/user-data/frontend.sh")

  root_block_device {
    volume_size = 8
    volume_type = "gp3"
  }

  tags = { Name = "${var.student_identity}-frontend" }
}

# ─── EC2 — Backend (Flask) ───

resource "aws_instance" "backend" {
  ami                         = data.aws_ssm_parameter.al2023_ami.value
  instance_type               = "t3.micro"
  associate_public_ip_address = true
  iam_instance_profile        = aws_iam_instance_profile.ec2_cloudwatch.name
  vpc_security_group_ids      = [aws_security_group.backend.id]
  user_data                   = file("${path.module}/user-data/backend.sh")

  root_block_device {
    volume_size = 8
    volume_type = "gp3"
  }

  tags = { Name = "${var.student_identity}-backend" }
}
