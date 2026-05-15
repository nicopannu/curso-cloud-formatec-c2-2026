#!/usr/bin/env bash
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

apt-get update
apt-get install -y postgresql postgresql-contrib

# Instalar SSM Agent (para AWS)
snap install amazon-ssm-agent --classic
systemctl enable snap.amazon-ssm-agent.amazon-ssm-agent.service
systemctl stop snap.amazon-ssm-agent.amazon-ssm-agent.service

# Configurar acceso SSH
bash /vagrant/scripts/local/configure-ssh-access.sh

sed -i "s/^#listen_addresses =.*/listen_addresses = '*'/" /etc/postgresql/14/main/postgresql.conf

if ! grep -q "192.168.56.0/24" /etc/postgresql/14/main/pg_hba.conf; then
  cat >>/etc/postgresql/14/main/pg_hba.conf <<'PGHBA'
host    all             all             192.168.56.0/24          scram-sha-256
PGHBA
fi

systemctl enable postgresql
systemctl restart postgresql

sudo -u postgres psql <<'SQL'
DO $$
BEGIN
   IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = 'cloudcuyo') THEN
      CREATE ROLE cloudcuyo LOGIN PASSWORD 'cloudcuyo';
   END IF;
END
$$;
SQL

sudo -u postgres psql <<'SQL'
SELECT 'CREATE DATABASE cloudcuyo OWNER cloudcuyo'
WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'cloudcuyo')\gexec
SQL

sudo -u postgres psql -d cloudcuyo -f /vagrant_db/schema.sql
sudo -u postgres psql -d cloudcuyo -f /vagrant_db/seed.sql

echo "db01 listo: postgresql://cloudcuyo:cloudcuyo@192.168.56.40:5432/cloudcuyo"

# Preparar VM para EC2
echo ""
echo "Preparando VM para migración a EC2..."
bash /vagrant/scripts/local/prepare-for-ec2.sh
