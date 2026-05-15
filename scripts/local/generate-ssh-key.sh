#!/usr/bin/env bash
# Script para generar SSH key para las VMs

set -e

KEY_DIR="/c/clase-redes"
KEY_FILE="$KEY_DIR/lab-key.pem"
PUB_FILE="$KEY_DIR/lab-key.pub"
PROJECT_PUB="./lab-key.pub"

echo "========================================="
echo "Generando SSH Key para CloudCuyo Labs"
echo "========================================="

# Crear directorio si no existe
mkdir -p "$KEY_DIR"

# Verificar si ya existe
if [ -f "$KEY_FILE" ]; then
    echo ""
    read -p "La key $KEY_FILE ya existe. ¿Sobrescribir? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Usando key existente"
        exit 0
    fi
    echo "Sobrescribiendo key existente..."
fi

# Generar nueva key
echo ""
echo "Generando nueva key RSA 4096 bits..."
ssh-keygen -t rsa -b 4096 -f "$KEY_FILE" -N "" -C "cloudcuyo-lab-key"

# Ajustar permisos
chmod 400 "$KEY_FILE"
chmod 644 "$PUB_FILE"

# Copiar public key al proyecto (para Vagrant)
cp "$PUB_FILE" "$PROJECT_PUB"

echo ""
echo "========================================="
echo "✓ SSH Key generada correctamente"
echo "========================================="
echo ""
echo "Private key: $KEY_FILE (400)"
echo "Public key:  $PUB_FILE (644)"
echo ""
echo "La key se usará para acceso SSH a las VMs:"
echo "  - Usuario: cloudadmin"
echo "  - Key: $KEY_FILE"
echo ""
echo "Ejemplo de conexión:"
echo "  ssh -i $KEY_FILE admin@<ip-instancia>"
echo ""
echo "Ahora puedes ejecutar: vagrant up"
