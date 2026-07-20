resource "aws_key_pair" "control" {
  key_name   = "${local.name_prefix}-control"
  public_key = file(pathexpand(var.control_public_key_path))
}

resource "aws_key_pair" "managed" {
  key_name   = "${local.name_prefix}-managed"
  public_key = file(pathexpand(var.managed_public_key_path))
}

module "ansible_control" {
  source = "./modules/ec2-instance"

  name                = "${local.name_prefix}-control"
  ami_id              = data.aws_ami.ubuntu.id
  instance_type       = var.instance_type
  subnet_id           = aws_subnet.public.id
  security_group_ids  = [aws_security_group.control.id]
  key_name            = aws_key_pair.control.key_name
  user_data           = templatefile("${path.module}/user-data/ansible-control.sh.tftpl", {})
  associate_public_ip = true
  additional_tags     = { Role = "ansible-control" }
}

module "web01" {
  source = "./modules/ec2-instance"

  name                = "${local.name_prefix}-web01"
  ami_id              = data.aws_ami.ubuntu.id
  instance_type       = var.instance_type
  subnet_id           = aws_subnet.public.id
  security_group_ids  = [aws_security_group.managed.id]
  key_name            = aws_key_pair.managed.key_name
  associate_public_ip = true
  additional_tags     = { Role = "managed-node", Node = "web01" }
}

module "web02" {
  source = "./modules/ec2-instance"

  name                = "${local.name_prefix}-web02"
  ami_id              = data.aws_ami.ubuntu.id
  instance_type       = var.instance_type
  subnet_id           = aws_subnet.public.id
  security_group_ids  = [aws_security_group.managed.id]
  key_name            = aws_key_pair.managed.key_name
  associate_public_ip = true
  additional_tags     = { Role = "managed-node", Node = "web02" }
}
