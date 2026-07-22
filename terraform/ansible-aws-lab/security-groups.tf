resource "aws_security_group" "control" {
  name        = "${local.name_prefix}-control-sg"
  description = "SSH al control node solamente desde la IP del alumno"
  vpc_id      = aws_vpc.lab.id

  ingress {
    description = "SSH desde student_cidr"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.student_cidr]
  }

  egress {
    description = "Salida necesaria para paquetes y gestion"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${local.name_prefix}-control-sg" }
}

resource "aws_security_group" "managed" {
  name        = "${local.name_prefix}-managed-sg"
  description = "SSH desde control node y HTTP desde la IP del alumno"
  vpc_id      = aws_vpc.lab.id

  ingress {
    description     = "SSH solamente desde el control node"
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [aws_security_group.control.id]
  }

  ingress {
    description = "HTTP de validacion desde student_cidr"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = [var.student_cidr]
  }

  ingress {
    description     = "HTTP interno desde el control node"
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.control.id]
  }

  egress {
    description = "Salida necesaria para instalar paquetes"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${local.name_prefix}-managed-sg" }
}
