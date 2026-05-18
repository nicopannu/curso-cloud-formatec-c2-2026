# Guia 1: REHOST Total - Importar OVAs a AWS EC2 (con NAT Instance)

**Objetivo:** Realizar una migración "lift and shift" completa de las VMs locales de CloudCuyo hacia AWS EC2, usando NAT Instance para acceso a Internet y administración via SSM.

**Duración estimada:** 3-4 horas

**Estrategia 6R:** **REHOST** (Lift and Shift) + **REPLACE** (NAT Gateway → NAT Instance)

---

## Contexto

CloudCuyo necesita migrar **urgentemente** a AWS debido a:

- Vencimiento del contrato del datacenter on-premise
- Necesidad de mayor disponibilidad
- Presión del negocio para estar en la nube lo antes posible

**Decisiones arquitectónicas:**

1. **REHOST:** Migración directa de VMs a EC2 (mínimo riesgo)
2. **NAT Instance vs NAT Gateway:** Usaremos NAT Instance para:
  - Reducir costos (~$10/mes vs $32/mes)
  - Propósito educativo (entender networking)
  - Permitir administración via SSM Session Manager

---

## Arquitectura objetivo

```
┌─────────────────────────────────────────────────────────────┐
│                        AWS Cloud                            │
│  ┌────────────────────────────────────────────────────┐    │
│  │  VPC (10.0.0.0/16)                                 │    │
│  │                                                     │    │
│  │  ┌────────────────────────────────────────────┐   │    │
│  │  │  Public Subnet (10.0.0.0/24)               │   │    │
│  │  │                                             │   │    │
│  │  │  ┌────────────┐  ┌────────────────────┐   │   │    │
│  │  │  │ NAT        │  │ LB01               │   │   │    │
│  │  │  │ Instance   │  │ (IP pública)       │   │   │    │
│  │  │  │ (EIP)      │  └────────────────────┘   │   │    │
│  │  │  └─────┬──────┘                            │   │    │
│  │  │        │ iptables MASQUERADE               │   │    │
│  │  └────────┼───────────────────────────────────┘   │    │
│  │           │                                        │    │
│  │  ┌────────▼───────────────────────────────────┐   │    │
│  │  │  Private Subnet (10.0.1.0/24)              │   │    │
│  │  │  Route: 0.0.0.0/0 → NAT Instance           │   │    │
│  │  │                                             │   │    │
│  │  │  ┌─────────────┐  ┌─────────────┐         │   │    │
│  │  │  │ FRONT01/02  │  │ API01       │         │   │    │
│  │  │  │ (privadas)  │  │ (privada)   │         │   │    │
│  │  │  └─────────────┘  └─────────────┘         │   │    │
│  │  │  ┌─────────────┐                         │   │    │
│  │  │  │ DB01        │                         │   │    │
│  │  │  │ (privada)   │                         │   │    │
│  │  │  └─────────────┘                         │   │    │
│  │  └─────────────────────────────────────────────┘   │    │
│  └────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────┘
         │                                    │
         │ SSM Session Manager                │ Updates/APIs
         └────────────────────────────────────┘
         (Administración sin SSH directo)
```

---

## Pre-requisitos

### Acceso a AWS Console

1. Acceder a [https://console.aws.amazon.com/](https://console.aws.amazon.com/)
2. Iniciar sesión con credenciales IAM
3. Región seleccionada: **us-east-1 (N. Virginia)**

**Infraestructura AWS existente (proporcionada por el instructor):**

Necesitarás los siguientes IDs de recursos ya creados:

- **VPC ID**: `vpc-xxxxxxxxx`
- **Public Subnet ID**: `subnet-xxxxxxxxx`
- **Private Subnet ID**: `subnet-xxxxxxxxx`
- **Private Route Table ID**: `rtb-xxxxxxxxx`
- **Key Pair Name**: `lab-key`

### OVAs del curso

Los archivos OVA utilizados en este lab son **exportaciones ya preparadas** de las VMs de CloudCuyo. Están preconfiguradas con SSM Agent, cloud-init y los drivers necesarios para funcionar en EC2.

Los archivos están disponibles en un bucket S3 público de solo lectura proporcionado para el curso:

```
s3://curso-cloud-c2-2026-ovas/
├── cloudcuyo-db01.ova         (PostgreSQL 14 + SSM Agent)
├── cloudcuyo-api01.ova        (Flask API + SSM Agent)
├── cloudcuyo-frontend01.ova   (NGINX web server + SSM Agent)
├── cloudcuyo-frontend02.ova   (NGINX web server + SSM Agent)
└── cloudcuyo-lb01.ova         (Load Balancer NGINX + SSM Agent)
```

> **Nota:** No es necesario descargar los OVAs a tu máquina local. En la Fase 2 de esta guia los copiarás directamente desde el bucket del curso a tu propio bucket usando AWS CloudShell (transferencia interna dentro de AWS).

> **¿Querés levantar las VMs localmente con Vagrant?** Si preferís regenerar los OVAs desde cero o simplemente explorar el entorno on-premise antes de migrarlo, ver `[vagrant/instrucciones-levantar-vms.md](../vagrant/instrucciones-levantar-vms.md)`.

**Alternativa: Verificar herramientas CLI (Bash/PowerShell)**

**Bash (Linux/Mac/WSL):**

```bash
# Verificar herramientas
aws --version       # AWS CLI >= 2.x
VBoxManage --version
vagrant --version

# Configurar AWS CLI
aws configure
# AWS Access Key ID: tu-access-key
# AWS Secret Access Key: tu-secret-key
# Default region: us-east-1
# Default output format: json

# Verificar configuración
aws sts get-caller-identity
```

**PowerShell (Windows):**

```powershell
# Instalar AWS Tools (si no está instalado)
Install-Module -Name AWS.Tools.Installer -Force
Install-AWSToolsModule AWS.Tools.EC2,AWS.Tools.S3,AWS.Tools.CloudFormation,AWS.Tools.SimpleSystemsManagement -CleanUp

# Configurar credenciales
Set-AWSCredential -AccessKey "tu-access-key" -SecretKey "tu-secret-key" -StoreAs default

Set-DefaultAWSRegion -Region us-east-1

# Verificar
Get-STSCallerIdentity
Get-Command VBoxManage
vagrant --version
```



---

## Fase 1: Desplegar NAT Instance

### 1.1. Desplegar con CloudFormation

**Usando AWS Console:**

1. Ir a **CloudFormation** en la consola de AWS
2. Click en **Create stack** > **With new resources (standard)**
3. En **Prerequisite - Prepare template:** seleccionar **Template is ready**
4. En **Specify template:** seleccionar **Upload a template file**
5. Click **Choose file** y seleccionar el archivo `cloudformation/nat-instance.yaml` del repositorio local
6. Click **Next**
7. **Stack name:** `cloudcuyo-nat`
8. **Parameters:**
  - **VpcId:** Pegar el VPC ID proporcionado por el instructor
  - **PublicSubnetId:** Pegar el Public Subnet ID proporcionado por el instructor
  - **PrivateRouteTableId:** Pegar el Private Route Table ID proporcionado por el instructor
  - **KeyPairName:** `lab-key`
  - **InstanceType:** `t3.micro`
9. Click **Next**
10. En **Configure stack options:** dejar todo por defecto, click **Next**
11. En **Review:** marcar la casilla **I acknowledge that AWS CloudFormation might create IAM resources with custom names**
12. Click **Submit**
13. Esperar a que el estado sea **CREATE_COMPLETE** (~5 minutos)
14. Ir a la pestaña **Outputs** y anotar:
  - **NATInstanceId:** ID de la instancia NAT
    - **SSMInstanceProfileName:** Nombre del perfil IAM para SSM (ejemplo: `cloudcuyo-nat-instance-profile-lab`)
    - **NATElasticIP:** IP elástica de la NAT instance

**Alternativa: Usando CLI (Bash/PowerShell)**

**Bash:**

```bash
source aws-ids.sh

aws cloudformation create-stack --stack-name cloudcuyo-nat --template-body file://cloudformation/nat-instance.yaml --parameters ParameterKey=VpcId,ParameterValue=$VPC_ID ParameterKey=PublicSubnetId,ParameterValue=$PUBLIC_SUBNET_ID ParameterKey=PrivateRouteTableId,ParameterValue=$PRIVATE_RT_ID ParameterKey=KeyPairName,ParameterValue=lab-key ParameterKey=InstanceType,ParameterValue=t3.micro --capabilities CAPABILITY_NAMED_IAM

echo "Esperando a que se complete el stack..."
aws cloudformation wait stack-create-complete --stack-name cloudcuyo-nat

echo "✓ NAT Instance desplegada"
aws cloudformation describe-stacks --stack-name cloudcuyo-nat --query 'Stacks[0].Outputs' --output table
```

**PowerShell:**

```powershell
. .\aws-ids.ps1

$Parameters = @(
    @{ ParameterKey = "VpcId"; ParameterValue = $VpcId }
    @{ ParameterKey = "PublicSubnetId"; ParameterValue = $PublicSubnetId }
    @{ ParameterKey = "PrivateRouteTableId"; ParameterValue = $PrivateRtId }
    @{ ParameterKey = "KeyPairName"; ParameterValue = "lab-key" }
    @{ ParameterKey = "InstanceType"; ParameterValue = "t3.micro" }
)

$TemplateBody = Get-Content -Path "cloudformation\nat-instance.yaml" -Raw

New-CFNStack -StackName "cloudcuyo-nat" -TemplateBody $TemplateBody -Parameter $Parameters -Capability CAPABILITY_NAMED_IAM

Write-Host "Esperando a que se complete el stack..." -ForegroundColor Yellow
Wait-CFNStack -StackName "cloudcuyo-nat" -Status CREATE_COMPLETE -Timeout 600

Write-Host "✓ NAT Instance desplegada" -ForegroundColor Green
$Stack = Get-CFNStack -StackName "cloudcuyo-nat"
$Stack.Outputs | Format-Table -Property OutputKey, OutputValue, Description
```



---

## Fase 2: Exportar VMs locales (o usar OVAs pre-exportados)

### Opción A: Usar OVAs pre-exportados (recomendado)

Si quieres ahorrar tiempo (~30-40 minutos), los OVAs están disponibles en el bucket S3:

```
s3://curso-cloud-c2-2026-ovas/
```

Los copiarás a tu propio bucket en la **Fase 3**.

**Ir directo a Fase 3**

---

### Opción B: Exportar tus propias VMs locales

### 2.1. Preparar y detener VMs

1. Abrir terminal en la carpeta del proyecto
2. Iniciar VMs: `vagrant up`
3. (Opcional) Limpiar archivos temporales para reducir tamaño:
  ```bash
   for vm in db01 api01 frontend01 frontend02 lb01; do
     vagrant ssh $vm -c "sudo apt-get clean && sudo rm -rf /tmp/* /var/tmp/*"
   done
  ```
4. Detener VMs: `vagrant halt`

### 2.2. Exportar a OVA usando VirtualBox GUI

**Para cada VM (db01, api01, frontend01, frontend02, lb01):**

1. Abrir **VirtualBox Manager**
2. Seleccionar la VM (ej: `cloudcuyo-db01`)
3. Click en **File** > **Export Appliance...**
4. Seleccionar la VM a exportar, click **Next**
5. **Format:** OVF 2.0
6. **File:** Elegir ubicación y nombre (ej: `C:\Users\<tu-usuario>\cloudcuyo-ovas\cloudcuyo-db01.ova`)
7. **MAC Address Policy:** Strip all network adapter MAC addresses
8. Click **Next**
9. (Opcional) Editar información (Name, Product, etc.)
10. Click **Export**
11. Esperar a que termine (~5-8 min por VM)

Repetir para las 5 VMs. **Tiempo total estimado: 30-40 minutos**

**Archivos resultantes:**

- `cloudcuyo-db01.ova` (~2-3 GB)
- `cloudcuyo-api01.ova` (~1-2 GB)
- `cloudcuyo-frontend01.ova` (~1-2 GB)
- `cloudcuyo-frontend02.ova` (~1-2 GB)
- `cloudcuyo-lb01.ova` (~1-2 GB)

**Alternativa: Usando CLI (Bash/PowerShell)**

**Bash:**

```bash
mkdir -p export-aws
cd export-aws

echo "Exportando VMs (esto toma ~30-40 minutos total)..."

VBoxManage export cloudcuyo-db01 --output cloudcuyo-db01.ova --ovf20 --options manifest,nomacs &
VBoxManage export cloudcuyo-api01 --output cloudcuyo-api01.ova --ovf20 --options manifest,nomacs &
VBoxManage export cloudcuyo-frontend01 --output cloudcuyo-frontend01.ova --ovf20 --options manifest,nomacs &
VBoxManage export cloudcuyo-frontend02 --output cloudcuyo-frontend02.ova --ovf20 --options manifest,nomacs &
VBoxManage export cloudcuyo-lb01 --output cloudcuyo-lb01.ova --ovf20 --options manifest,nomacs &

wait

ls -lh *.ova
echo "✓ Exportación completada"
```

**PowerShell:**

```powershell
New-Item -ItemType Directory -Force -Path "export-aws"
Set-Location "export-aws"

Write-Host "Exportando VMs (esto toma ~30-40 minutos total)..." -ForegroundColor Yellow

$jobs = @()
$vms = @("cloudcuyo-db01", "cloudcuyo-api01", "cloudcuyo-frontend01", "cloudcuyo-frontend02", "cloudcuyo-lb01")

foreach ($vm in $vms) {
    $jobs += Start-Job -ScriptBlock {
        param($vmName)
        & "C:\Program Files\Oracle\VirtualBox\VBoxManage.exe" export $vmName --output "$vmName.ova" --ovf20 --options manifest,nomacs
    } -ArgumentList $vm
}

# Esperar a que terminen todos
$jobs | Wait-Job | Receive-Job
$jobs | Remove-Job

Get-ChildItem *.ova | Format-Table Name, Length
Write-Host "✓ Exportación completada" -ForegroundColor Green
```



---

## Fase 3: Crear bucket S3 y copiar OVAs desde bucket público

### 3.1. Crear bucket S3 (GUI)

**Usando AWS Console:**

1. Ir a **S3** en la consola de AWS
2. Click en **Create bucket**
3. Configurar:
  - **Bucket name:** `cloudcuyo-vm-import-<tu-numero-unico>` (ej: `cloudcuyo-vm-import-20260513`)
  - **AWS Region:** `us-east-1`
  - **Block Public Access settings:** Dejar todo marcado (seguridad por defecto)
  - Resto de opciones: dejar por defecto
4. Click **Create bucket**
5. **Anotar el nombre exacto del bucket**

### 3.2. Copiar OVAs usando CloudShell (recomendado)

**Usando AWS CloudShell:**

1. En la consola de AWS, click en el ícono de **CloudShell** (parte superior derecha, junto a la campana de notificaciones)
2. Esperar a que cargue el terminal (~30 seg)
3. Crear variable con tu bucket:
  ```bash
   MY_BUCKET="cloudcuyo-vm-import-$(aws sts get-caller-identity --query Account --output text)"
   echo $MY_BUCKET
  ```
4. Copiar los OVAs desde el bucket público a tu bucket (sin descargar, red interna de AWS):
  ```bash
   aws s3 cp s3://curso-cloud-c2-2026-ovas/cloudcuyo-db01.ova s3://$MY_BUCKET/ --no-progress
   aws s3 cp s3://curso-cloud-c2-2026-ovas/cloudcuyo-api01.ova s3://$MY_BUCKET/ --no-progress
   aws s3 cp s3://curso-cloud-c2-2026-ovas/cloudcuyo-frontend01.ova s3://$MY_BUCKET/ --no-progress
   aws s3 cp s3://curso-cloud-c2-2026-ovas/cloudcuyo-frontend02.ova s3://$MY_BUCKET/ --no-progress
   aws s3 cp s3://curso-cloud-c2-2026-ovas/cloudcuyo-lb01.ova s3://$MY_BUCKET/ --no-progress
  ```
5. Esto tomará ~10-15 minutos (los archivos se copian por la red interna de AWS, no pasan por tu computadora)
6. Verificar que se copiaron:
  ```bash
   aws s3 ls s3://$MY_BUCKET/
  ```

**Ventajas de CloudShell:**

- No descargar/subir los OVAs (~5-8 GB)
- Copia directa entre buckets S3 (red interna AWS)
- Más rápido y sin consumir ancho de banda local
- No requiere instalar AWS CLI localmente

### 3.3. Alternativa: Subir OVAs locales

**Si exportaste los OVAs localmente con VirtualBox (GUI o CLI)**

**Usando AWS Console:**

1. Ir al bucket recién creado
2. Click en **Upload**
3. Click en **Add files** o arrastra los 5 archivos OVA
4. Seleccionar:
  - `cloudcuyo-db01.ova`
  - `cloudcuyo-api01.ova`
  - `cloudcuyo-frontend01.ova`
  - `cloudcuyo-frontend02.ova`
  - `cloudcuyo-lb01.ova`
5. (Opcional) Expandir **Additional upload options** > **Storage class:** Standard
6. Click **Upload**
7. Esperar a que termine (~30-60 minutos dependiendo de tu conexión)
8. Verificar que los 5 archivos estén en el bucket

**Alternativa: Usando CLI (Bash/PowerShell)**

**Bash:**

```bash
source ../aws-ids.sh

# Crear bucket único
BUCKET_NAME="cloudcuyo-vm-import-$(date +%s)"
aws s3 mb s3://${BUCKET_NAME} --region $AWS_REGION

echo "Subiendo OVAs a S3 (esto toma ~30-60 minutos)..."

# Subir en paralelo
aws s3 cp cloudcuyo-db01.ova s3://${BUCKET_NAME}/ &
aws s3 cp cloudcuyo-api01.ova s3://${BUCKET_NAME}/ &
aws s3 cp cloudcuyo-frontend01.ova s3://${BUCKET_NAME}/ &
aws s3 cp cloudcuyo-frontend02.ova s3://${BUCKET_NAME}/ &
aws s3 cp cloudcuyo-lb01.ova s3://${BUCKET_NAME}/ &

wait

aws s3 ls s3://${BUCKET_NAME}/
echo "BUCKET_NAME=$BUCKET_NAME" >> ../aws-ids.sh
echo "✓ OVAs subidas a S3"
```

**PowerShell:**

```powershell
. ..\aws-ids.ps1

# Crear bucket único
$BucketName = "cloudcuyo-vm-import-$(Get-Date -Format 'yyyyMMddHHmmss')"
New-S3Bucket -BucketName $BucketName -Region $Region

Write-Host "Subiendo OVAs a S3 (esto toma ~30-60 minutos)..." -ForegroundColor Yellow

# Subir en paralelo
$uploadJobs = @()
$files = Get-ChildItem *.ova

foreach ($file in $files) {
    $uploadJobs += Start-Job -ScriptBlock {
        param($bucket, $filePath)
        Write-S3Object -BucketName $bucket -File $filePath -Key (Split-Path $filePath -Leaf)
    } -ArgumentList $BucketName, $file.FullName
}

$uploadJobs | Wait-Job | Receive-Job
$uploadJobs | Remove-Job

Get-S3Object -BucketName $BucketName | Format-Table Key, Size
"`$BucketName = `"$BucketName`"" | Add-Content -Path "..\aws-ids.ps1"
Write-Host "✓ OVAs subidas a S3" -ForegroundColor Green
```



---

## Fase 4: Importar VMs como AMIs

### 4.1. Importar usando CloudShell (simplificado)

**Usando AWS CloudShell:**

1. En la consola de AWS, click en el icono de **CloudShell**
2. Esperar a que cargue (~30 seg)
3. Definir variable con tu bucket:
  ```bash
   MY_BUCKET="cloudcuyo-vm-import-$(aws sts get-caller-identity --query Account --output text)"
  ```
4. Crear archivos de configuracion para cada VM:

**DB01:**

```bash
cat > db01-import.json <<EOF
[
  {
    "Description": "CloudCuyo DB01",
    "Format": "ova",
    "UserBucket": {
      "S3Bucket": "$MY_BUCKET",
      "S3Key": "cloudcuyo-db01.ova"
    }
  }
]
EOF
```

**API01:**

```bash
cat > api01-import.json <<EOF
[
  {
    "Description": "CloudCuyo API01",
    "Format": "ova",
    "UserBucket": {
      "S3Bucket": "$MY_BUCKET",
      "S3Key": "cloudcuyo-api01.ova"
    }
  }
]
EOF
```

**Frontend01:**

```bash
cat > frontend01-import.json <<EOF
[
  {
    "Description": "CloudCuyo Frontend01",
    "Format": "ova",
    "UserBucket": {
      "S3Bucket": "$MY_BUCKET",
      "S3Key": "cloudcuyo-frontend01.ova"
    }
  }
]
EOF
```

**Frontend02:**

```bash
cat > frontend02-import.json <<EOF
[
  {
    "Description": "CloudCuyo Frontend02",
    "Format": "ova",
    "UserBucket": {
      "S3Bucket": "$MY_BUCKET",
      "S3Key": "cloudcuyo-frontend02.ova"
    }
  }
]
EOF
```

**LB01:**

```bash
cat > lb01-import.json <<EOF
[
  {
    "Description": "CloudCuyo LB01",
    "Format": "ova",
    "UserBucket": {
      "S3Bucket": "$MY_BUCKET",
      "S3Key": "cloudcuyo-lb01.ova"
    }
  }
]
EOF
```

1. Iniciar las importaciones:

```bash
# Importar DB01
DB_TASK=$(aws ec2 import-image --description "CloudCuyo DB01" --disk-containers file://db01-import.json --query 'ImportTaskId' --output text)
echo "DB01 Import Task: $DB_TASK"

# Importar API01
API_TASK=$(aws ec2 import-image --description "CloudCuyo API01" --disk-containers file://api01-import.json --query 'ImportTaskId' --output text)
echo "API01 Import Task: $API_TASK"

# Importar Frontend01
FRONT01_TASK=$(aws ec2 import-image --description "CloudCuyo Frontend01" --disk-containers file://frontend01-import.json --query 'ImportTaskId' --output text)
echo "Frontend01 Import Task: $FRONT01_TASK"

# Importar Frontend02
FRONT02_TASK=$(aws ec2 import-image --description "CloudCuyo Frontend02" --disk-containers file://frontend02-import.json --query 'ImportTaskId' --output text)
echo "Frontend02 Import Task: $FRONT02_TASK"

# Importar LB01
LB_TASK=$(aws ec2 import-image --description "CloudCuyo LB01" --disk-containers file://lb01-import.json --query 'ImportTaskId' --output text)
echo "LB01 Import Task: $LB_TASK"

echo ""
echo "✓ Todas las importaciones iniciadas"
echo "Tiempo estimado: 20-30 minutos"
```

1. **Tomar un cafe** - Las importaciones tardan ~20-30 minutos
2. Verificar progreso (opcional):

```bash
aws ec2 describe-import-image-tasks --import-task-ids $DB_TASK $API_TASK $FRONT01_TASK $FRONT02_TASK $LB_TASK
```

1. Cuando terminen, obtener los AMI IDs:

```bash
DB_AMI=$(aws ec2 describe-import-image-tasks --import-task-ids $DB_TASK --query 'ImportImageTasks[0].ImageId' --output text)
API_AMI=$(aws ec2 describe-import-image-tasks --import-task-ids $API_TASK --query 'ImportImageTasks[0].ImageId' --output text)
FRONT01_AMI=$(aws ec2 describe-import-image-tasks --import-task-ids $FRONT01_TASK --query 'ImportImageTasks[0].ImageId' --output text)
FRONT02_AMI=$(aws ec2 describe-import-image-tasks --import-task-ids $FRONT02_TASK --query 'ImportImageTasks[0].ImageId' --output text)
LB_AMI=$(aws ec2 describe-import-image-tasks --import-task-ids $LB_TASK --query 'ImportImageTasks[0].ImageId' --output text)

echo "DB01 AMI: $DB_AMI"
echo "API01 AMI: $API_AMI"
echo "Frontend01 AMI: $FRONT01_AMI"
echo "Frontend02 AMI: $FRONT02_AMI"
echo "LB01 AMI: $LB_AMI"
```

1. Etiquetar las AMIs importadas con nombres claros:

> VM Import/Export genera el nombre interno de la AMI con el ID de la tarea (`import-ami-...`). Para evitar confusiones al lanzar instancias, agregar un tag `Name` descriptivo apenas termina la importacion.

```bash
aws ec2 create-tags --resources $DB_AMI --tags Key=Name,Value=cloudcuyo-db01-ami Key=Role,Value=database Key=Lab,Value=m2-c1-lab
aws ec2 create-tags --resources $API_AMI --tags Key=Name,Value=cloudcuyo-api01-ami Key=Role,Value=api Key=Lab,Value=m2-c1-lab
aws ec2 create-tags --resources $FRONT01_AMI --tags Key=Name,Value=cloudcuyo-frontend01-ami Key=Role,Value=frontend Key=Lab,Value=m2-c1-lab
aws ec2 create-tags --resources $FRONT02_AMI --tags Key=Name,Value=cloudcuyo-frontend02-ami Key=Role,Value=frontend Key=Lab,Value=m2-c1-lab
aws ec2 create-tags --resources $LB_AMI --tags Key=Name,Value=cloudcuyo-lb01-ami Key=Role,Value=load-balancer Key=Lab,Value=m2-c1-lab

aws ec2 describe-images \
  --image-ids $DB_AMI $API_AMI $FRONT01_AMI $FRONT02_AMI $LB_AMI \
  --query 'Images[].{AMI:ImageId,Nombre:Tags[?Key==`Name`]|[0].Value,Estado:State,Descripcion:Description}' \
  --output table
```

**Mientras esperas las importaciones:**

- Puedes avanzar con la siguiente fase (crear Security Groups)
- Revisar la documentacion de arquitectura
- Tomar un descanso

---

## Fase 5: Lanzar instancias EC2

Esta fase se realiza desde la **AWS Console**. Usar CloudShell solo para validaciones o troubleshooting.

> **Importante:** si existe un Load Balancer (`LB01`) público, los servidores `frontend01` y `frontend02` no necesitan IP pública ni subnet pública. El diseño recomendado es: `LB01` en subnet pública, `frontend01`, `frontend02`, `api01` y `db01` en subnet privada. El Security Group del frontend debe aceptar HTTP solo desde el Security Group del LB.

### 5.1. Identificar datos necesarios

Antes de lanzar instancias, anotar estos valores desde la consola:

- VPC del laboratorio: usar la VPC provista por el instructor.
- Public subnet: subnet donde se lanzará `lb01`.
- Private subnet: subnet donde se lanzarán `frontend01`, `frontend02`, `api01` y `db01`.
- Key pair: key pair provisto por el instructor.
- Instance Profile SSM: output `SSMInstanceProfileName` del stack `cloudcuyo-nat` en CloudFormation.
- AMIs importadas: AMIs con tags `cloudcuyo-db01-ami`, `cloudcuyo-api01-ami`, `cloudcuyo-frontend01-ami`, `cloudcuyo-frontend02-ami` y `cloudcuyo-lb01-ami`.

IPs privadas sugeridas, ajustarlas al CIDR real de la subnet privada:

| Instancia | Subnet | IP publica | IP privada sugerida |
|---|---|---|---|
| `lb01` | Public subnet | Si | Asignada automaticamente |
| `frontend01` | Private subnet | No | `10.0.1.20` |
| `frontend02` | Private subnet | No | `10.0.1.21` |
| `api01` | Private subnet | No | `10.0.1.30` |
| `db01` | Private subnet | No | `10.0.1.40` |

### 5.2. Crear Security Groups desde la consola

Ir a **EC2 > Security Groups > Create security group** y crear los siguientes grupos en la VPC del laboratorio.

**Security Group LB**

| Campo | Valor |
|---|---|
| Name | `cloudcuyo-lb-sg` |
| Description | `CloudCuyo public load balancer` |
| Inbound rule | HTTP TCP 80 desde `0.0.0.0/0` |
| Outbound rule | All traffic o HTTP TCP 80 hacia la VPC |

**Security Group Frontend**

| Campo | Valor |
|---|---|
| Name | `cloudcuyo-frontend-sg` |
| Description | `CloudCuyo private frontend` |
| Inbound rule | HTTP TCP 80 desde `cloudcuyo-lb-sg` |
| Outbound rule | All traffic o hacia `cloudcuyo-api-sg` |

**Security Group API**

| Campo | Valor |
|---|---|
| Name | `cloudcuyo-api-sg` |
| Description | `CloudCuyo private API` |
| Inbound rule | TCP 5000 desde `cloudcuyo-frontend-sg` |
| Outbound rule | All traffic o PostgreSQL hacia `cloudcuyo-db-sg` |

**Security Group DB**

| Campo | Valor |
|---|---|
| Name | `cloudcuyo-db-sg` |
| Description | `CloudCuyo private database` |
| Inbound rule | TCP 5432 desde `cloudcuyo-api-sg` |
| Outbound rule | All traffic |

No agregar reglas inbound para SSM. Session Manager usa conexiones salientes desde la instancia hacia AWS Systems Manager.

### 5.3. Lanzar `db01` en subnet privada

1. Ir a **EC2 > AMIs**.
2. Buscar la AMI `cloudcuyo-db01-ami`.
3. Seleccionarla y elegir **Launch instance from AMI**.
4. Name: `cloudcuyo-db01`.
5. Instance type: `t3.medium`.
6. Key pair: seleccionar el key pair del laboratorio.
7. Network settings: elegir la VPC del laboratorio.
8. Subnet: seleccionar la private subnet.
9. Auto-assign public IP: `Disable`.
10. Firewall: seleccionar `cloudcuyo-db-sg`.
11. Advanced network configuration: configurar la IP privada sugerida para DB, por ejemplo `10.0.1.40` si pertenece a tu subnet privada.
12. Advanced details: en **IAM instance profile**, seleccionar el Instance Profile SSM del stack `cloudcuyo-nat`.
13. Revisar y elegir **Launch instance**.

### 5.4. Lanzar `api01` en subnet privada

1. Repetir el flujo desde **EC2 > AMIs** usando `cloudcuyo-api01-ami`.
2. Name: `cloudcuyo-api01`.
3. Instance type: `t3.small`.
4. Subnet: private subnet.
5. Auto-assign public IP: `Disable`.
6. Firewall: seleccionar `cloudcuyo-api-sg`.
7. IP privada sugerida: `10.0.1.30` si pertenece a tu subnet privada.
8. IAM instance profile: seleccionar el Instance Profile SSM del stack `cloudcuyo-nat`.
9. Lanzar la instancia.

### 5.5. Lanzar `frontend01` y `frontend02` en subnet privada

1. Repetir el flujo desde **EC2 > AMIs** usando `cloudcuyo-frontend01-ami`.
2. Name: `cloudcuyo-frontend01`.
3. Instance type: `t3.micro`.
4. Subnet: private subnet.
5. Auto-assign public IP: `Disable`.
6. Firewall: seleccionar `cloudcuyo-frontend-sg`.
7. IP privada sugerida: `10.0.1.20` si pertenece a tu subnet privada.
8. IAM instance profile: seleccionar el Instance Profile SSM del stack `cloudcuyo-nat`.
9. Lanzar la instancia.
10. Repetir con `cloudcuyo-frontend02-ami`.
11. Name: `cloudcuyo-frontend02`.
12. IP privada sugerida: `10.0.1.21` si pertenece a tu subnet privada.

### 5.6. Lanzar `lb01` en subnet publica

1. Repetir el flujo desde **EC2 > AMIs** usando `cloudcuyo-lb01-ami`.
2. Name: `cloudcuyo-lb01`.
3. Instance type: `t3.micro`.
4. Subnet: public subnet.
5. Auto-assign public IP: `Enable`.
6. Firewall: seleccionar `cloudcuyo-lb-sg`.
7. IAM instance profile: seleccionar el Instance Profile SSM del stack `cloudcuyo-nat`.
8. Lanzar la instancia.
9. Cuando quede `Running`, copiar su **Public IPv4 address**. Ese será el endpoint público inicial del lab.

### 5.7. Verificar estado inicial

1. Ir a **EC2 > Instances**.
2. Confirmar que las cinco instancias estén en estado `Running`.
3. Confirmar que `lb01` tenga IP pública.
4. Confirmar que `frontend01`, `frontend02`, `api01` y `db01` no tengan IP pública.
5. Confirmar que cada instancia tenga el IAM Instance Profile de SSM asociado.
6. Ir a **Systems Manager > Fleet Manager** o **Session Manager**.
7. Validar que las instancias aparezcan como administradas por SSM.

Si una instancia no aparece como `Online`, revisar que tenga asociado el Instance Profile de SSM y conectividad de salida por NAT o endpoints privados de SSM. Si el agente muestra errores de credenciales, reiniciar la instancia desde **EC2 > Instances > Instance state > Reboot instance**.

---

## Fase 6: Verificación y administración via SSM

### 6.1. Conectar via Session Manager

Opcion recomendada por GUI:

1. Ir a **Systems Manager > Session Manager**.
2. Click en **Start session**.
3. Seleccionar la instancia `cloudcuyo-db01`.
4. Click en **Start session**.
5. Dentro de la sesion, validar servicios:

```bash
sudo su -
systemctl status postgresql
psql -U cloudcuyo -d cloudcuyo
```

### 6.2. Verificar conectividad

Usar la IP publica de `cloudcuyo-lb01` copiada desde **EC2 > Instances > Public IPv4 address**.

```bash
LB_PUBLIC_IP=<ip-publica-de-lb01>

# Health check
curl http://$LB_PUBLIC_IP/api/health

# Portal
curl -I http://$LB_PUBLIC_IP/portal.html

# API pública
curl http://$LB_PUBLIC_IP/api/v1/health
```

---

## Costos estimados


| Recurso            | Tipo         | Costo/mes (us-east-1) |
| ------------------ | ------------ | --------------------- |
| NAT Instance       | t3.micro     | ~$7                   |
| DB01               | t3.medium    | ~$30                  |
| API01              | t3.small     | ~$15                  |
| Frontend01/02      | t3.micro × 2 | ~$15                  |
| LB01               | t3.micro     | ~$7                   |
| Elastic IPs        | 1 (NAT)      | ~$3.50                |
| EBS (5 instancias) | ~50GB total  | ~$5                   |
| Data Transfer      | ~10GB/mes    | ~$1                   |
| **TOTAL**          |              | **~$87/mes**          |


---

## Limpieza

Priorizar limpieza desde **AWS CloudShell**. Si algun comando falla porque una variable no existe, revisar los IDs en la consola de EC2 y completar la variable correspondiente antes de continuar.

### Opcion A: CloudShell / AWS CLI

```bash
export AWS_PROFILE=curso
export AWS_REGION=us-east-1

# Terminar instancias
aws ec2 terminate-instances \
  --profile curso \
  --region us-east-1 \
  --instance-ids "$DB_INSTANCE" "$API_INSTANCE" "$FRONT01_INSTANCE" "$FRONT02_INSTANCE" "$LB_INSTANCE"

aws ec2 wait instance-terminated \
  --profile curso \
  --region us-east-1 \
  --instance-ids "$DB_INSTANCE" "$API_INSTANCE" "$FRONT01_INSTANCE" "$FRONT02_INSTANCE" "$LB_INSTANCE"

# Eliminar Security Groups creados por el lab
aws ec2 delete-security-group --profile curso --region us-east-1 --group-id "$DB_SG"
aws ec2 delete-security-group --profile curso --region us-east-1 --group-id "$API_SG"
aws ec2 delete-security-group --profile curso --region us-east-1 --group-id "$FRONT_SG"
aws ec2 delete-security-group --profile curso --region us-east-1 --group-id "$LB_SG"

# Guardar snapshots asociados antes de deregistrar las AMIs
DB_SNAPSHOT_ID=$(aws ec2 describe-images --profile curso --region us-east-1 --image-ids "$DB_AMI" --query 'Images[0].BlockDeviceMappings[0].Ebs.SnapshotId' --output text)
API_SNAPSHOT_ID=$(aws ec2 describe-images --profile curso --region us-east-1 --image-ids "$API_AMI" --query 'Images[0].BlockDeviceMappings[0].Ebs.SnapshotId' --output text)
FRONT01_SNAPSHOT_ID=$(aws ec2 describe-images --profile curso --region us-east-1 --image-ids "$FRONT01_AMI" --query 'Images[0].BlockDeviceMappings[0].Ebs.SnapshotId' --output text)
FRONT02_SNAPSHOT_ID=$(aws ec2 describe-images --profile curso --region us-east-1 --image-ids "$FRONT02_AMI" --query 'Images[0].BlockDeviceMappings[0].Ebs.SnapshotId' --output text)
LB_SNAPSHOT_ID=$(aws ec2 describe-images --profile curso --region us-east-1 --image-ids "$LB_AMI" --query 'Images[0].BlockDeviceMappings[0].Ebs.SnapshotId' --output text)

# Deregistrar AMIs importadas
aws ec2 deregister-image --profile curso --region us-east-1 --image-id "$DB_AMI"
aws ec2 deregister-image --profile curso --region us-east-1 --image-id "$API_AMI"
aws ec2 deregister-image --profile curso --region us-east-1 --image-id "$FRONT01_AMI"
aws ec2 deregister-image --profile curso --region us-east-1 --image-id "$FRONT02_AMI"
aws ec2 deregister-image --profile curso --region us-east-1 --image-id "$LB_AMI"

# Eliminar snapshots asociados a las AMIs importadas
aws ec2 delete-snapshot --profile curso --region us-east-1 --snapshot-id "$DB_SNAPSHOT_ID"
aws ec2 delete-snapshot --profile curso --region us-east-1 --snapshot-id "$API_SNAPSHOT_ID"
aws ec2 delete-snapshot --profile curso --region us-east-1 --snapshot-id "$FRONT01_SNAPSHOT_ID"
aws ec2 delete-snapshot --profile curso --region us-east-1 --snapshot-id "$FRONT02_SNAPSHOT_ID"
aws ec2 delete-snapshot --profile curso --region us-east-1 --snapshot-id "$LB_SNAPSHOT_ID"

# Eliminar CloudFormation stack (NAT instance)
aws cloudformation delete-stack \
  --profile curso \
  --region us-east-1 \
  --stack-name cloudcuyo-nat

# Limpiar S3
aws s3 rm "s3://${MY_BUCKET}" --recursive --profile curso --region us-east-1
aws s3 rb "s3://${MY_BUCKET}" --profile curso --region us-east-1
```

No eliminar la VPC base del laboratorio salvo que el instructor lo indique. Normalmente la VPC, subnets, route tables e Internet Gateway son infraestructura compartida o preexistente del curso.

### Opcion B: AWS Console

1. Ir a **EC2 > Instances**.
2. Seleccionar las instancias `cloudcuyo-db01`, `cloudcuyo-api01`, `cloudcuyo-frontend01`, `cloudcuyo-frontend02` y `cloudcuyo-lb01`.
3. Click en **Instance state > Terminate instance** y esperar a estado `Terminated`.
4. Ir a **EC2 > AMIs**.
5. Seleccionar las AMIs importadas del lab y elegir **Actions > Deregister AMI**.
6. Ir a **EC2 > Snapshots**.
7. Filtrar por snapshots propios creados por esas AMIs y eliminarlos.
8. Ir a **EC2 > Security Groups**.
9. Eliminar los security groups creados por el lab: DB, API, Frontend y LB.
10. Ir a **CloudFormation > Stacks**.
11. Seleccionar `cloudcuyo-nat` y elegir **Delete**.
12. Ir a **S3**.
13. Vaciar el bucket de importacion de OVAs y luego eliminarlo.

Antes de cerrar el lab, verificar que no queden instancias corriendo, AMIs importadas, snapshots, buckets temporales ni security groups creados para la practica.

---

## Próximos desafíos

Una vez completado este lab, has logrado:

- Migrar infraestructura on-premise a AWS EC2 (REHOST)
- Implementar networking con NAT Instance
- Administrar instancias via SSM Session Manager
- Entender costos de infraestructura cloud

**Próximos labs recomendados:**

- **Lab 2:** Modernizar frontend con S3 + CloudFront (REPLATFORM) - Ver `docs/lab-02-frontend-s3-cloudfront.md`
- **Próximos desafíos:** Refactorizar API a serverless, migrar DB a RDS
