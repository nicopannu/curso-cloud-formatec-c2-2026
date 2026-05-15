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

rm -rf /var/www/cloudcuyo
mkdir -p /var/www/cloudcuyo
cp -R /vagrant_app/frontend/. /var/www/cloudcuyo/
chown -R www-data:www-data /var/www/cloudcuyo

cat >/etc/nginx/sites-available/cloudcuyo-frontend.conf <<'NGINX'
server {
    listen 80 default_server;
    server_name frontend01 cloudcuyo.local _;

    root /var/www/cloudcuyo;
    index index.html;

    location / {
        try_files $uri $uri/ /index.html;
    }
}
NGINX

rm -f /etc/nginx/sites-enabled/default
ln -sf /etc/nginx/sites-available/cloudcuyo-frontend.conf /etc/nginx/sites-enabled/cloudcuyo-frontend.conf
nginx -t
systemctl enable nginx
systemctl restart nginx

echo "frontend01 listo: http://192.168.56.20"

# Preparar VM para EC2
echo ""
echo "Preparando VM para migración a EC2..."
bash /vagrant/scripts/local/prepare-for-ec2.sh
