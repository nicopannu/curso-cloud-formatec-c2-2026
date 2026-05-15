#!/usr/bin/env bash
# Script para preparar VMs Ubuntu para ser importadas como AMIs en EC2
set -euo pipefail

echo "========================================="
echo "Preparando VM para EC2"
echo "========================================="

export DEBIAN_FRONTEND=noninteractive

# ============================================================================
# 1. INSTALAR Y CONFIGURAR CLOUD-INIT (CRÍTICO PARA EC2)
# ============================================================================

echo ""
echo "=== 1. Instalando cloud-init ==="

apt-get update -qq
apt-get install -y cloud-init

# Configurar cloud-init para EC2
cat > /etc/cloud/cloud.cfg.d/90_ec2.cfg <<'EOF'
# Configuración específica para AWS EC2
datasource_list: [ Ec2, None ]
datasource:
  Ec2:
    timeout: 50
    max_wait: 120
    metadata_urls: ['http://169.254.169.254']

# Deshabilitar configuración de red por cloud-init (usar netplan/systemd)
network:
  config: disabled

# Módulos de cloud-init para EC2
cloud_init_modules:
 - migrator
 - seed_random
 - bootcmd
 - write-files
 - growpart
 - resizefs
 - disk_setup
 - mounts
 - set_hostname
 - update_hostname
 - update_etc_hosts
 - ca-certs
 - rsyslog
 - users-groups
 - ssh

cloud_config_modules:
 - emit_upstart
 - snap
 - ssh-import-id
 - locale
 - set-passwords
 - grub-dpkg
 - apt-pipelining
 - apt-configure
 - ubuntu-advantage
 - ntp
 - timezone
 - disable-ec2-metadata
 - runcmd
 - byobu

cloud_final_modules:
 - package-update-upgrade-install
 - fan
 - landscape
 - lxd
 - ubuntu-drivers
 - write-files-deferred
 - puppet
 - chef
 - mcollective
 - salt-minion
 - reset_rmc
 - refresh_rmc_and_interface
 - rightscale_userdata
 - scripts-vendor
 - scripts-per-once
 - scripts-per-boot
 - scripts-per-instance
 - scripts-user
 - ssh-authkey-fingerprints
 - keys-to-console
 - phone-home
 - final-message
 - power-state-change

# System info
system_info:
  default_user:
    name: ubuntu
    lock_passwd: True
    gecos: Ubuntu
    groups: [adm, audio, cdrom, dialout, dip, floppy, lxd, netdev, plugdev, sudo, video]
    sudo: ["ALL=(ALL) NOPASSWD:ALL"]
    shell: /bin/bash
  package_mirrors:
    - arches: [i386, amd64]
      failsafe:
        primary: http://archive.ubuntu.com/ubuntu
        security: http://security.ubuntu.com/ubuntu
EOF

echo "✓ cloud-init instalado y configurado para EC2"

# ============================================================================
# 2. CREAR USUARIO SSM-USER (RECOMENDADO POR AWS)
# ============================================================================

echo ""
echo "=== 2. Configurando usuario ssm-user ==="

# Crear usuario ssm-user si no existe
if ! id ssm-user &>/dev/null; then
    useradd -m -s /bin/bash ssm-user
    echo "✓ Usuario ssm-user creado"
else
    echo "✓ Usuario ssm-user ya existe"
fi

# Agregar a sudoers sin password
echo "ssm-user ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/ssm-user
chmod 0440 /etc/sudoers.d/ssm-user

echo "✓ ssm-user configurado con sudo sin password"

# ============================================================================
# 3. VERIFICAR DRIVERS PARA EC2 (ENA, NVME)
# ============================================================================

echo ""
echo "=== 3. Verificando drivers para EC2 ==="

# Verificar que los módulos necesarios estén disponibles
MODULES_OK=true

# ENA (Elastic Network Adapter)
if ! modinfo ena &>/dev/null; then
    echo "⚠ Módulo ENA no disponible (puede ser normal en kernel moderno)"
    MODULES_OK=false
fi

# NVMe para EBS
if ! modinfo nvme &>/dev/null; then
    echo "⚠ Módulo NVMe no disponible"
    MODULES_OK=false
fi

if [ "$MODULES_OK" = true ]; then
    echo "✓ Drivers de red y disco verificados"
fi

# ============================================================================
# 4. CONFIGURAR NETPLAN PARA DHCP (EC2 usa DHCP)
# ============================================================================

echo ""
echo "=== 4. Configurando red para DHCP ==="

# Backup de configuración actual
if [ -f /etc/netplan/01-netcfg.yaml ]; then
    cp /etc/netplan/01-netcfg.yaml /etc/netplan/01-netcfg.yaml.bak
fi

# Configuración simple DHCP para EC2
cat > /etc/netplan/50-cloud-init.yaml <<'EOF'
# Configuración de red para EC2
network:
  version: 2
  ethernets:
    eth0:
      dhcp4: true
      dhcp6: false
      optional: true
    ens5:
      dhcp4: true
      dhcp6: false
      optional: true
EOF

chmod 600 /etc/netplan/50-cloud-init.yaml

echo "✓ Netplan configurado para DHCP"

# ============================================================================
# 5. CONFIGURAR SSH PARA EC2
# ============================================================================

echo ""
echo "=== 5. Configurando SSH para EC2 ==="

# Asegurar que SSH permita login con keys
sed -i 's/^#*PubkeyAuthentication.*/PubkeyAuthentication yes/' /etc/ssh/sshd_config
sed -i 's/^#*PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config
sed -i 's/^#*PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config
sed -i 's/^#*UsePAM.*/UsePAM yes/' /etc/ssh/sshd_config

# Asegurar que cloud-init pueda gestionar authorized_keys
sed -i 's/^#*AuthorizedKeysFile.*/AuthorizedKeysFile .ssh\/authorized_keys .ssh\/authorized_keys2/' /etc/ssh/sshd_config

echo "✓ SSH configurado para EC2"

# ============================================================================
# 6. CONFIGURAR SSM AGENT PARA EC2
# ============================================================================

echo ""
echo "=== 6. Configurando SSM Agent ==="

# Asegurar que SSM Agent está habilitado pero no corriendo (se inicia en EC2)
systemctl enable snap.amazon-ssm-agent.amazon-ssm-agent.service
systemctl stop snap.amazon-ssm-agent.amazon-ssm-agent.service 2>/dev/null || true

# Limpiar cualquier configuración local de SSM
rm -rf /var/lib/amazon/ssm/registration 2>/dev/null || true
rm -rf /var/lib/amazon/ssm/Vault/Store 2>/dev/null || true

echo "✓ SSM Agent configurado para EC2"

# ============================================================================
# 7. INSTALAR HERRAMIENTAS ÚTILES PARA EC2
# ============================================================================

echo ""
echo "=== 7. Instalando herramientas EC2 ==="

apt-get install -y \
    awscli \
    python3-boto3 \
    ec2-instance-connect \
    curl \
    wget \
    jq

echo "✓ Herramientas EC2 instaladas"

# ============================================================================
# 8. PREPARAR PARA EXPORT (LIMPIEZA)
# ============================================================================

echo ""
echo "=== 8. Limpiando sistema para export ==="

# Limpiar cache de apt
apt-get clean
apt-get autoclean

# Limpiar logs (pero mantener directorios)
find /var/log -type f -name "*.log" -exec truncate -s 0 {} \;
find /var/log -type f -name "*.gz" -delete
find /var/log -type f -name "*.1" -delete
journalctl --vacuum-time=1s 2>/dev/null || true

# Limpiar temporal
rm -rf /tmp/*
rm -rf /var/tmp/*

# Limpiar cache de usuario
rm -rf /home/*/.cache/* 2>/dev/null || true

# Limpiar bash history
rm -f /home/*/.bash_history 2>/dev/null || true
rm -f /root/.bash_history 2>/dev/null || true
history -c

# Limpiar cloud-init data (se regenera en EC2)
cloud-init clean --logs --seed

# NO remover SSH host keys todavía (se removerán antes del export final)
# Se hace en un paso separado justo antes de apagar

echo "✓ Sistema limpiado para export"

# ============================================================================
# 9. CONFIGURAR HOSTNAME DINÁMICO
# ============================================================================

echo ""
echo "=== 9. Configurando hostname dinámico ==="

# Permitir que cloud-init gestione el hostname
cat > /etc/cloud/cloud.cfg.d/99_hostname.cfg <<'EOF'
# Configurar hostname desde EC2 metadata
preserve_hostname: false
manage_etc_hosts: true
EOF

echo "✓ Hostname configurado para ser dinámico en EC2"

# ============================================================================
# 10. VERIFICACIÓN FINAL
# ============================================================================

echo ""
echo "========================================="
echo "VERIFICACIÓN FINAL"
echo "========================================="

echo ""
echo "✓ cloud-init instalado: $(cloud-init --version)"
echo "✓ SSM Agent: $(snap list amazon-ssm-agent | grep amazon-ssm-agent | awk '{print $2}')"
echo "✓ AWS CLI: $(aws --version | head -1)"

echo ""
echo "Usuarios configurados para EC2:"
id ubuntu 2>/dev/null && echo "  ✓ ubuntu (creado por cloud-init)" || echo "  ⚠ ubuntu (será creado por cloud-init)"
id ssm-user 2>/dev/null && echo "  ✓ ssm-user (para SSM Session Manager)"
id cloudadmin 2>/dev/null && echo "  ✓ cloudadmin (backup, con password y key)"

echo ""
echo "Servicios habilitados:"
systemctl is-enabled snap.amazon-ssm-agent.amazon-ssm-agent.service && echo "  ✓ SSM Agent"
systemctl is-enabled ssh && echo "  ✓ SSH"
systemctl is-enabled cloud-init && echo "  ✓ cloud-init"

echo ""
echo "========================================="
echo "✓ VM PREPARADA PARA EC2"
echo "========================================="
echo ""
echo "La VM está configurada con:"
echo "  ✓ cloud-init para EC2"
echo "  ✓ ssm-user para SSM Session Manager"
echo "  ✓ cloudadmin para acceso SSH de respaldo"
echo "  ✓ Drivers EC2 (ENA, NVMe)"
echo "  ✓ Red DHCP"
echo "  ✓ SSM Agent listo"
echo ""
echo "NOTA: finalize-for-export.sh se ejecutará automáticamente antes del export"
echo ""
