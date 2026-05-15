#!/usr/bin/env bash
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

apt-get update
apt-get install -y python3 python3-venv python3-pip curl

# Instalar SSM Agent (para AWS)
snap install amazon-ssm-agent --classic
systemctl enable snap.amazon-ssm-agent.amazon-ssm-agent.service
systemctl stop snap.amazon-ssm-agent.amazon-ssm-agent.service

# Configurar acceso SSH
bash /vagrant/scripts/local/configure-ssh-access.sh

mkdir -p /opt/cloudcuyo-api
cp -R /vagrant_app/api/. /opt/cloudcuyo-api/

python3 -m venv /opt/cloudcuyo-api/.venv
/opt/cloudcuyo-api/.venv/bin/pip install --upgrade pip
/opt/cloudcuyo-api/.venv/bin/pip install -r /opt/cloudcuyo-api/requirements.txt

cat >/etc/systemd/system/cloudcuyo-api.service <<'SYSTEMD'
[Unit]
Description=CloudCuyo legacy API
After=network-online.target
Wants=network-online.target

[Service]
WorkingDirectory=/opt/cloudcuyo-api
Environment=DB_HOST=192.168.56.40
Environment=DB_NAME=cloudcuyo
Environment=DB_USER=cloudcuyo
Environment=DB_PASSWORD=cloudcuyo
Environment=APP_NODE=api01
ExecStart=/opt/cloudcuyo-api/.venv/bin/gunicorn --bind 0.0.0.0:5000 app:app
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
SYSTEMD

systemctl daemon-reload
systemctl enable cloudcuyo-api
systemctl restart cloudcuyo-api

echo "api01 listo: http://192.168.56.30:5000/api/health"

# Preparar VM para EC2
echo ""
echo "Preparando VM para migración a EC2..."
bash /vagrant/scripts/local/prepare-for-ec2.sh
