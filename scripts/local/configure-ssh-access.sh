#!/usr/bin/env bash
# Script para configurar acceso SSH con key y password
# Se ejecuta en cada VM durante el provisión

set -euo pipefail

echo "Configurando acceso SSH..."

# Crear usuario cloudadmin con password (evitamos usar 'admin' que puede existir)
useradd -m -s /bin/bash cloudadmin 2>/dev/null || true
echo "cloudadmin:admin1234" | chpasswd

# Agregar cloudadmin a sudoers sin password
echo "cloudadmin ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/cloudadmin
chmod 0440 /etc/sudoers.d/cloudadmin

# Configurar SSH para permitir password authentication
sed -i 's/^#*PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config
sed -i 's/^#*PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config

# Crear directorio .ssh para cloudadmin
mkdir -p /home/cloudadmin/.ssh
chmod 700 /home/cloudadmin/.ssh

# Agregar public key desde archivo local (si existe)
if [ -f /vagrant/lab-key.pub ]; then
    cat /vagrant/lab-key.pub > /home/cloudadmin/.ssh/authorized_keys
    chmod 600 /home/cloudadmin/.ssh/authorized_keys
    chown -R cloudadmin:cloudadmin /home/cloudadmin/.ssh
    echo "✓ Public key agregada para usuario cloudadmin"
else
    echo "⚠ No se encontró /vagrant/lab-key.pub - generar key primero"
fi

# Reiniciar SSH
systemctl restart sshd

echo "✓ Acceso SSH configurado:"
echo "  - Usuario: cloudadmin"
echo "  - Password: admin1234"
echo "  - SSH Key: /home/cloudadmin/.ssh/authorized_keys"
