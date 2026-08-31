resource "aws_security_group" "nat" {
  name        = "${local.name_prefix}-nat-sg"
  description = "NAT instance traffic for private lab subnets"
  vpc_id      = aws_vpc.this.id

  ingress {
    description = "HTTPS from application subnets through NAT"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["10.41.10.0/23", "10.41.20.0/23"]
  }

  egress {
    description = "Outbound Internet access"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${local.name_prefix}-nat-sg"
  }
}

resource "aws_security_group" "backend" {
  name        = "${local.name_prefix}-backend-sg"
  description = "Backend instances without public ingress"
  vpc_id      = aws_vpc.this.id

  egress {
    description = "DNS UDP to VPC resolver"
    from_port   = 53
    to_port     = 53
    protocol    = "udp"
    cidr_blocks = ["10.41.0.0/16"]
  }

  egress {
    description = "DNS TCP to VPC resolver"
    from_port   = 53
    to_port     = 53
    protocol    = "tcp"
    cidr_blocks = ["10.41.0.0/16"]
  }

  egress {
    description = "HTTPS to Systems Manager and AWS service endpoints"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${local.name_prefix}-backend-sg"
  }
}

resource "aws_instance" "nat" {
  ami                         = data.aws_ami.amazon_linux.id
  instance_type               = "t3.micro"
  subnet_id                   = aws_subnet.public["public-az1"].id
  associate_public_ip_address = true
  source_dest_check           = false
  vpc_security_group_ids      = [aws_security_group.nat.id]

  user_data_replace_on_change = true
  user_data                   = <<-USERDATA
    #!/bin/bash
    set -euxo pipefail

    if command -v dnf >/dev/null 2>&1; then
      dnf install -y iptables-services
    else
      yum install -y iptables-services
    fi

    sysctl -w net.ipv4.ip_forward=1
    printf 'net.ipv4.ip_forward = 1\n' >/etc/sysctl.d/99-nat.conf
    iptables -A FORWARD -s 10.41.0.0/16 -o $(ip route show default | awk '{print $5; exit}') -j ACCEPT
    iptables -A FORWARD -d 10.41.0.0/16 -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
    iptables -t nat -A POSTROUTING -s 10.41.0.0/16 -o $(ip route show default | awk '{print $5; exit}') -j MASQUERADE
    service iptables save || true
    systemctl enable --now iptables || true
  USERDATA

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }

  tags = {
    Name = "${local.name_prefix}-nat-01"
    Role = "nat-instance"
  }
}

resource "aws_instance" "backend" {
  for_each = local.backend_instances

  ami                         = data.aws_ami.amazon_linux.id
  instance_type               = "t3.micro"
  subnet_id                   = aws_subnet.private_app[each.value.subnet_key].id
  associate_public_ip_address = false
  iam_instance_profile        = aws_iam_instance_profile.backend[each.key].name
  vpc_security_group_ids      = [aws_security_group.backend.id]

  user_data_replace_on_change = true
  user_data                   = <<-USERDATA
    #!/bin/bash
    set -euxo pipefail

    if command -v dnf >/dev/null 2>&1; then
      dnf install -y amazon-ssm-agent awscli jq postgresql15
    else
      yum install -y amazon-ssm-agent awscli jq
    fi

    systemctl enable --now amazon-ssm-agent
  USERDATA

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }

  root_block_device {
    encrypted = true
  }

  tags = {
    Name = "${local.name_prefix}-${each.key}"
    Role = each.value.group
  }
}
