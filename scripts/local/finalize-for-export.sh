#!/usr/bin/env bash
# Script para finalizar preparación de VMs antes del export a OVA
# Este script debe ejecutarse DESPUÉS de prepare-for-ec2.sh y justo ANTES de apagar la VM
set -euo pipefail

echo "========================================="
echo "Finalizando VM para export como OVA"
echo "========================================="

export DEBIAN_FRONTEND=noninteractive

# ============================================================================
# 1. REMOVER SSH HOST KEYS (SE REGENERAN EN EC2)
# ============================================================================

echo ""
echo "=== 1. Removiendo SSH host keys ==="
echo "Estos se regenerarán automáticamente en EC2 en el primer boot"

rm -f /etc/ssh/ssh_host_*
echo "✓ SSH host keys removidas"

# ============================================================================
# 2. LIMPIAR ARCHIVOS TEMPORALES FINALES
# ============================================================================

echo ""
echo "=== 2. Limpieza final de archivos temporales ==="

# Limpiar bash history (puede contener comandos sensibles)
cat /dev/null > ~/.bash_history
history -c

# Limpiar journald completamente
journalctl --vacuum-time=1s 2>/dev/null || true

# Limpiar dhcp leases (se renovarán en EC2)
rm -f /var/lib/dhcp/dhclient.*

# Limpiar udev rules persistentes (se regeneran para nuevo hardware)
rm -f /etc/udev/rules.d/70-persistent-net.rules

echo "✓ Archivos temporales limpiados"

# ============================================================================
# 3. REMOVER DATOS DE CLOUD-INIT (SE REGENERAN EN EC2)
# ============================================================================

echo ""
echo "=== 3. Limpiando datos de cloud-init ==="

# Forzar cloud-init a ejecutarse en próximo boot (EC2)
cloud-init clean --logs --seed

echo "✓ cloud-init listo para primer boot en EC2"

# ============================================================================
# 4. LIMPIAR MACHINE-ID (SE REGENERA EN EC2)
# ============================================================================

echo ""
echo "=== 4. Limpiando machine-id ==="

# Truncar machine-id (systemd lo regenerará en próximo boot)
truncate -s 0 /etc/machine-id
rm -f /var/lib/dbus/machine-id
ln -sf /etc/machine-id /var/lib/dbus/machine-id

echo "✓ machine-id limpiado (se regenerará en EC2)"

# ============================================================================
# 5. SYNC FILESYSTEM
# ============================================================================

echo ""
echo "=== 5. Sincronizando filesystem ==="

sync

echo "✓ Filesystem sincronizado"

# ============================================================================
# VERIFICACIÓN FINAL
# ============================================================================

echo ""
echo "========================================="
echo "VERIFICACIÓN FINAL"
echo "========================================="

echo ""
echo "Verificando que componentes críticos fueron removidos:"
[ ! -f /etc/ssh/ssh_host_rsa_key ] && echo "  ✓ SSH host keys removidas" || echo "  ⚠ SSH host keys AÚN EXISTEN"
[ ! -f /var/lib/dhcp/dhclient.leases ] && echo "  ✓ DHCP leases limpios" || echo "  ⚠ DHCP leases presentes"
[ ! -s /etc/machine-id ] && echo "  ✓ machine-id truncado" || echo "  ⚠ machine-id tiene contenido"

echo ""
echo "Verificando que componentes críticos están presentes:"
[ -f /etc/cloud/cloud.cfg.d/90_ec2.cfg ] && echo "  ✓ cloud-init configurado para EC2" || echo "  ⚠ cloud-init config FALTA"
id ssm-user &>/dev/null && echo "  ✓ ssm-user existe" || echo "  ⚠ ssm-user NO existe"
id cloudadmin &>/dev/null && echo "  ✓ cloudadmin existe" || echo "  ⚠ cloudadmin NO existe"
systemctl is-enabled snap.amazon-ssm-agent.amazon-ssm-agent.service &>/dev/null && echo "  ✓ SSM Agent habilitado" || echo "  ⚠ SSM Agent NO habilitado"

echo ""
echo "========================================="
echo "✓ VM LISTA PARA EXPORT COMO OVA"
echo "========================================="
echo ""
echo "Próximos pasos:"
echo "  1. Apagar la VM: sudo poweroff"
echo "  2. Exportar con VBoxManage export"
echo "  3. Subir OVA a S3"
echo "  4. Importar en AWS con aws ec2 import-image"
echo ""
echo "Una vez en EC2, la VM:"
echo "  - Generará nuevas SSH host keys"
echo "  - Obtendrá configuración via cloud-init"
echo "  - Registrará SSM Agent con Systems Manager"
echo "  - Obtendrá IP via DHCP de VPC"
echo "  - Estará lista para acceso via SSM o SSH"
echo ""
