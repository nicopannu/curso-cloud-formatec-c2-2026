#!/bin/bash
# =============================================================================
# CloudCuyo - Crear VPC base en us-east-1 (zona A)
# Uso: bash create-vpc.sh
# Ejecutar desde AWS CloudShell
# =============================================================================

set -e

REGION="us-east-1"
AZ="${REGION}a"
PROJECT="cloudcuyo"

VPC_CIDR="10.0.0.0/16"
PUBLIC_CIDR="10.0.1.0/24"
PRIVATE_CIDR="10.0.2.0/24"

echo "============================================="
echo " CloudCuyo - Creando infraestructura de red"
echo "============================================="

# --- VPC ---
echo ""
echo "[1/7] Creando VPC $VPC_CIDR..."
VPC_ID=$(aws ec2 create-vpc \
  --cidr-block "$VPC_CIDR" \
  --region "$REGION" \
  --query 'Vpc.VpcId' \
  --output text)

aws ec2 modify-vpc-attribute --vpc-id "$VPC_ID" --enable-dns-hostnames
aws ec2 modify-vpc-attribute --vpc-id "$VPC_ID" --enable-dns-support
aws ec2 create-tags --resources "$VPC_ID" --tags Key=Name,Value="${PROJECT}-vpc"
echo "  VPC: $VPC_ID"

# --- Internet Gateway ---
echo ""
echo "[2/7] Creando Internet Gateway..."
IGW_ID=$(aws ec2 create-internet-gateway \
  --region "$REGION" \
  --query 'InternetGateway.InternetGatewayId' \
  --output text)

aws ec2 attach-internet-gateway --internet-gateway-id "$IGW_ID" --vpc-id "$VPC_ID"
aws ec2 create-tags --resources "$IGW_ID" --tags Key=Name,Value="${PROJECT}-igw"
echo "  IGW: $IGW_ID"

# --- Subnet pública ---
echo ""
echo "[3/7] Creando subnet pública $PUBLIC_CIDR en $AZ..."
PUBLIC_SUBNET_ID=$(aws ec2 create-subnet \
  --vpc-id "$VPC_ID" \
  --cidr-block "$PUBLIC_CIDR" \
  --availability-zone "$AZ" \
  --query 'Subnet.SubnetId' \
  --output text)

aws ec2 modify-subnet-attribute --subnet-id "$PUBLIC_SUBNET_ID" --map-public-ip-on-launch
aws ec2 create-tags --resources "$PUBLIC_SUBNET_ID" --tags Key=Name,Value="${PROJECT}-subnet-public-a"
echo "  Subnet pública: $PUBLIC_SUBNET_ID"

# --- Subnet privada ---
echo ""
echo "[4/7] Creando subnet privada $PRIVATE_CIDR en $AZ..."
PRIVATE_SUBNET_ID=$(aws ec2 create-subnet \
  --vpc-id "$VPC_ID" \
  --cidr-block "$PRIVATE_CIDR" \
  --availability-zone "$AZ" \
  --query 'Subnet.SubnetId' \
  --output text)

aws ec2 create-tags --resources "$PRIVATE_SUBNET_ID" --tags Key=Name,Value="${PROJECT}-subnet-private-a"
echo "  Subnet privada: $PRIVATE_SUBNET_ID"

# --- Route table pública ---
echo ""
echo "[5/7] Creando route table pública..."
PUBLIC_RT_ID=$(aws ec2 create-route-table \
  --vpc-id "$VPC_ID" \
  --query 'RouteTable.RouteTableId' \
  --output text)

aws ec2 create-route --route-table-id "$PUBLIC_RT_ID" --destination-cidr-block "0.0.0.0/0" --gateway-id "$IGW_ID"
aws ec2 associate-route-table --route-table-id "$PUBLIC_RT_ID" --subnet-id "$PUBLIC_SUBNET_ID"
aws ec2 create-tags --resources "$PUBLIC_RT_ID" --tags Key=Name,Value="${PROJECT}-rt-public"
echo "  RT pública: $PUBLIC_RT_ID"

# --- Route table privada ---
echo ""
echo "[6/7] Creando route table privada..."
PRIVATE_RT_ID=$(aws ec2 create-route-table \
  --vpc-id "$VPC_ID" \
  --query 'RouteTable.RouteTableId' \
  --output text)

aws ec2 associate-route-table --route-table-id "$PRIVATE_RT_ID" --subnet-id "$PRIVATE_SUBNET_ID"
aws ec2 create-tags --resources "$PRIVATE_RT_ID" --tags Key=Name,Value="${PROJECT}-rt-private"
echo "  RT privada: $PRIVATE_RT_ID"

# --- Exportar IDs ---
echo ""
echo "[7/7] Guardando IDs en aws-ids.sh..."
cat > aws-ids.sh <<EOF
# CloudCuyo - IDs de infraestructura AWS
# Generado: $(date)
export AWS_REGION="$REGION"
export VPC_ID="$VPC_ID"
export IGW_ID="$IGW_ID"
export PUBLIC_SUBNET_ID="$PUBLIC_SUBNET_ID"
export PRIVATE_SUBNET_ID="$PRIVATE_SUBNET_ID"
export PUBLIC_RT_ID="$PUBLIC_RT_ID"
export PRIVATE_RT_ID="$PRIVATE_RT_ID"
EOF

echo ""
echo "============================================="
echo " Infraestructura creada exitosamente"
echo "============================================="
echo "  VPC:             $VPC_ID  ($VPC_CIDR)"
echo "  IGW:             $IGW_ID"
echo "  Subnet pública:  $PUBLIC_SUBNET_ID  ($PUBLIC_CIDR)"
echo "  Subnet privada:  $PRIVATE_SUBNET_ID  ($PRIVATE_CIDR)"
echo "  RT pública:      $PUBLIC_RT_ID"
echo "  RT privada:      $PRIVATE_RT_ID"
echo ""
echo "  IDs guardados en: aws-ids.sh"
echo "  Usar con: source aws-ids.sh"
echo "============================================="
