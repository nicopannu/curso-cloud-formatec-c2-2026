#!/usr/bin/env bash
set -e

echo "========================================="
echo "Regenerando VMs con SSM Agent"
echo "========================================="

# Destruir VMs existentes
echo "1. Destruyendo VMs existentes..."
vagrant destroy -f

# Recrear VMs con nuevos scripts
echo "2. Creando VMs con SSM Agent preinstalado..."
vagrant up

echo ""
echo "3. Esperando 30 segundos para que las VMs se estabilicen..."
sleep 30

echo ""
echo "4. Finalizando preparación de VMs para export..."
VMS=("db01" "api01" "frontend01" "frontend02" "lb01")

for vm in "${VMS[@]}"; do
    echo "Finalizando ${vm}..."
    vagrant ssh "$vm" -c "sudo bash /vagrant/scripts/local/finalize-for-export.sh"
done

# Crear directorio de exports si no existe
EXPORT_DIR="/c/Users/Nico/exports-ova"
mkdir -p "$EXPORT_DIR"

echo ""
echo "5. Apagando VMs para exportar..."
vagrant halt

echo ""
echo "========================================="
echo "Exportando OVAs"
echo "========================================="

# Eliminar OVAs previos si existen
rm -f "$EXPORT_DIR"/*.ova

# Exportar cada VM

for vm in "${VMS[@]}"; do
    echo ""
    echo "Exportando cloudcuyo-${vm}..."
    VBoxManage export "$vm" -o "$EXPORT_DIR/cloudcuyo-${vm}.ova" --ovf20 --manifest
    echo "✓ cloudcuyo-${vm}.ova exportado"
done

echo ""
echo "========================================="
echo "✓ Proceso completado"
echo "========================================="
echo ""
echo "OVAs exportados en: $EXPORT_DIR"
echo ""
ls -lh "$EXPORT_DIR"/*.ova

echo ""
echo "Ahora puedes:"
echo "1. Subir los OVAs a S3: aws s3 sync $EXPORT_DIR s3://curso-cloud-c2-2026-ovas/ --acl public-read"
echo "2. O iniciar Vagrant de nuevo: vagrant up"
