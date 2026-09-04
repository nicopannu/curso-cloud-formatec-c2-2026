resource "aws_db_subnet_group" "rds" {
  name       = "${local.name_prefix}-rds-subnets"
  subnet_ids = data.aws_subnets.db.ids

  tags = {
    Name = "${local.name_prefix}-rds-subnets"
  }
}

resource "aws_security_group" "rds" {
  name        = "${local.name_prefix}-rds-sg"
  description = "RDS PostgreSQL lab: initial VPC-wide connectivity before SG hardening"
  vpc_id      = data.aws_vpc.foundation.id

  ingress {
    description = "Initial lab state: PostgreSQL reachable from the foundation VPC"
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = [data.aws_vpc.foundation.cidr_block]
  }

  egress {
    description = "Stateful response traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${local.name_prefix}-rds-sg"
  }
}

resource "aws_security_group" "backend_b_source" {
  name        = "${local.name_prefix}-backend-b-rds-source-sg"
  description = "Identity-only source SG attached to backend-b for RDS access"
  vpc_id      = data.aws_vpc.foundation.id

  tags = {
    Name = "${local.name_prefix}-backend-b-rds-source-sg"
  }
}

resource "aws_network_interface_sg_attachment" "backend_b_source" {
  for_each = toset(data.aws_network_interfaces.backend_b.ids)

  security_group_id    = aws_security_group.backend_b_source.id
  network_interface_id = each.value
}

resource "aws_vpc_security_group_egress_rule" "backend_to_rds" {
  security_group_id            = data.aws_security_group.backend.id
  referenced_security_group_id = aws_security_group.rds.id
  ip_protocol                  = "tcp"
  from_port                    = 5432
  to_port                      = 5432
  description                  = "Allow backend instances to reach PostgreSQL RDS"
}

resource "aws_db_parameter_group" "postgres" {
  name   = "${local.name_prefix}-postgres18"
  family = "postgres18"

  parameter {
    name         = "rds.force_ssl"
    value        = "1"
    apply_method = "pending-reboot"
  }

  tags = {
    Name = "${local.name_prefix}-postgres18"
  }
}

resource "aws_db_instance" "rds" {
  identifier                  = "${local.name_prefix}-rds"
  engine                      = "postgres"
  engine_version              = "18.3"
  instance_class              = "db.t3.micro"
  allocated_storage           = 20
  max_allocated_storage       = 20
  storage_type                = "gp3"
  storage_encrypted           = true
  kms_key_id                  = data.aws_kms_key.rds.arn
  db_name                     = "securitylab"
  username                    = "labadmin"
  manage_master_user_password = true
  publicly_accessible         = false
  multi_az                    = false
  db_subnet_group_name        = aws_db_subnet_group.rds.name
  vpc_security_group_ids      = [aws_security_group.rds.id]
  parameter_group_name        = aws_db_parameter_group.postgres.name
  backup_retention_period     = 1
  deletion_protection         = false
  skip_final_snapshot         = true
  apply_immediately           = true
  copy_tags_to_snapshot       = true

  tags = {
    Name = "${local.name_prefix}-rds"
  }
}

resource "aws_iam_role_policy" "backend_b_rds_secret" {
  for_each = data.aws_iam_role.backend_b

  name = "rds-secret-read-only"
  role = each.value.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid      = "ReadOnlyRdsMasterSecret"
      Effect   = "Allow"
      Action   = ["secretsmanager:DescribeSecret", "secretsmanager:GetSecretValue"]
      Resource = aws_db_instance.rds.master_user_secret[0].secret_arn
    }]
  })

  depends_on = [aws_db_instance.rds]
}
