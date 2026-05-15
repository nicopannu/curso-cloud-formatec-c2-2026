#!/usr/bin/env bash
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

apt-get update
apt-get install -y nginx curl

# Instalar SSM Agent (para AWS)
snap install amazon-ssm-agent --classic
systemctl enable snap.amazon-ssm-agent.amazon-ssm-agent.service
systemctl stop snap.amazon-ssm-agent.amazon-ssm-agent.service

# Configurar acceso SSH
bash /vagrant/scripts/local/configure-ssh-access.sh

cat >/etc/nginx/sites-available/cloudcuyo.conf <<'NGINX'
upstream cloudcuyo_frontend {
    server 192.168.56.20:80;
    server 192.168.56.21:80;
}

upstream cloudcuyo_api {
    server 192.168.56.30:5000;
}

server {
    listen 80 default_server;
    server_name cloudcuyo.local _;

    location /api/ {
        proxy_pass http://cloudcuyo_api/api/;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    }

    location / {
        proxy_pass http://cloudcuyo_frontend;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    }
}
NGINX

rm -f /etc/nginx/sites-enabled/default
ln -sf /etc/nginx/sites-available/cloudcuyo.conf /etc/nginx/sites-enabled/cloudcuyo.conf
nginx -t
systemctl enable nginx
systemctl restart nginx

echo "lb01 listo: http://192.168.56.10"

# Preparar VM para EC2
echo ""
echo "Preparando VM para migración a EC2..."
bash /vagrant/scripts/local/prepare-for-ec2.sh
