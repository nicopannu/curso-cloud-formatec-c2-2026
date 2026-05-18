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
│  │  │  Public Subnet (10.0.1.0/24)               │   │    │
│  │  │                                             │   │    │
│  │  │  ┌────────────┐  ┌────────────────────┐   │   │    │
│  │  │  │ NAT        │  │ LB01 + FRONT01/02  │   │   │    │
│  │  │  │ Instance   │  │ (IPs públicas)     │   │   │    │
│  │  │  │ (EIP)      │  └────────────────────┘   │   │    │
│  │  │  └─────┬──────┘                            │   │    │
│  │  │        │ iptables MASQUERADE               │   │    │
│  │  └────────┼───────────────────────────────────┘   │    │
│  │           │                                        │    │
│  │  ┌────────▼───────────────────────────────────┐   │    │
│  │  │  Private Subnet (10.0.2.0/24)              │   │    │
│  │  │  Route: 0.0.0.0/0 → NAT Instance           │   │    │
│  │  │                                             │   │    │
│  │  │  ┌─────────────┐  ┌─────────────┐         │   │    │
│  │  │  │ API01       │  │ DB01        │         │   │    │
│  │  │  │ (privada)   │  │ (privada)   │         │   │    │
│  │  │  │ SSM Agent   │  │ SSM Agent   │         │   │    │
│  │  │  └─────────────┘  └─────────────┘         │   │    │
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
- **Key Pair Name**: `cloudcuyo-key`

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
7. **Stack name:** `cloudcuyo-nat-instance`
8. **Parameters:**
  - **VpcId:** Pegar el VPC ID proporcionado por el instructor
  - **PublicSubnetId:** Pegar el Public Subnet ID proporcionado por el instructor
  - **PrivateRouteTableId:** Pegar el Private Route Table ID proporcionado por el instructor
  - **KeyPairName:** `cloudcuyo-key`
  - **InstanceType:** `t3.micro`
9. Click **Next**
10. En **Configure stack options:** dejar todo por defecto, click **Next**
11. En **Review:** marcar la casilla **I acknowledge that AWS CloudFormation might create IAM resources with custom names**
12. Click **Submit**
13. Esperar a que el estado sea **CREATE_COMPLETE** (~5 minutos)
14. Ir a la pestaña **Outputs** y anotar:
  - **NATInstanceId:** ID de la instancia NAT
    - **SSMInstanceProfileName:** Nombre del perfil IAM para SSM (ejemplo: `cloudcuyo-nat-instance-SSMInstanceProfile-ABC123`)
    - **NATElasticIP:** IP elástica de la NAT instance

**Alternativa: Usando CLI (Bash/PowerShell)**

**Bash:**

```bash
source aws-ids.sh

aws cloudformation create-stack --stack-name cloudcuyo-nat-instance --template-body file://cloudformation/nat-instance.yaml --parameters ParameterKey=VpcId,ParameterValue=$VPC_ID ParameterKey=PublicSubnetId,ParameterValue=$PUBLIC_SUBNET_ID ParameterKey=PrivateRouteTableId,ParameterValue=$PRIVATE_RT_ID ParameterKey=KeyPairName,ParameterValue=cloudcuyo-key ParameterKey=InstanceType,ParameterValue=t3.micro --capabilities CAPABILITY_NAMED_IAM

echo "Esperando a que se complete el stack..."
aws cloudformation wait stack-create-complete --stack-name cloudcuyo-nat-instance

echo "✓ NAT Instance desplegada"
aws cloudformation describe-stacks --stack-name cloudcuyo-nat-instance --query 'Stacks[0].Outputs' --output table
```

**PowerShell:**

```powershell
. .\aws-ids.ps1

$Parameters = @(
    @{ ParameterKey = "VpcId"; ParameterValue = $VpcId }
    @{ ParameterKey = "PublicSubnetId"; ParameterValue = $PublicSubnetId }
    @{ ParameterKey = "PrivateRouteTableId"; ParameterValue = $PrivateRtId }
    @{ ParameterKey = "KeyPairName"; ParameterValue = "cloudcuyo-key" }
    @{ ParameterKey = "InstanceType"; ParameterValue = "t3.micro" }
)

$TemplateBody = Get-Content -Path "cloudformation\nat-instance.yaml" -Raw

New-CFNStack -StackName "cloudcuyo-nat-instance" -TemplateBody $TemplateBody -Parameter $Parameters -Capability CAPABILITY_NAMED_IAM

Write-Host "Esperando a que se complete el stack..." -ForegroundColor Yellow
Wait-CFNStack -StackName "cloudcuyo-nat-instance" -Status CREATE_COMPLETE -Timeout 600

Write-Host "✓ NAT Instance desplegada" -ForegroundColor Green
$Stack = Get-CFNStack -StackName "cloudcuyo-nat-instance"
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
DB_TASK=$(aws ec2 import-image --description "CloudCuyo DB01" --disk-containers "file://db01-import.json" --query 'ImportTaskId' --output text)
echo "DB01 Import Task: $DB_TASK"

# Importar API01
API_TASK=$(aws ec2 import-image --description "CloudCuyo API01" --disk-containers "file://api01-import.json" --query 'ImportTaskId' --output text)
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

**Alternativa: Usando CLI local (Bash/PowerShell)**

**Bash:**

```bash
source aws-ids.sh

# Crear archivos de containers
for vm in db01 api01 frontend01 frontend02 lb01; do
  cat > ${vm}-containers.json <<EOF
{
  "Description": "CloudCuyo $vm",
  "Format": "ova",
  "UserBucket": {
    "S3Bucket": "${BUCKET_NAME}",
    "S3Key": "cloudcuyo-${vm}.ova"
  }
}
EOF
done

# Importar VMs
DB_IMPORT=$(aws ec2 import-image --description "CloudCuyo DB01" --disk-containers file://db01-containers.json --query 'ImportTaskId' --output text)
API_IMPORT=$(aws ec2 import-image --description "CloudCuyo API01" --disk-containers file://api01-containers.json --query 'ImportTaskId' --output text)
FRONT01_IMPORT=$(aws ec2 import-image --description "CloudCuyo Frontend01" --disk-containers file://frontend01-containers.json --query 'ImportTaskId' --output text)
FRONT02_IMPORT=$(aws ec2 import-image --description "CloudCuyo Frontend02" --disk-containers file://frontend02-containers.json --query 'ImportTaskId' --output text)
LB_IMPORT=$(aws ec2 import-image --description "CloudCuyo LB01" --disk-containers file://lb01-containers.json --query 'ImportTaskId' --output text)

echo "Tasks de importacion iniciadas"
echo "Monitorear progreso con: aws ec2 describe-import-image-tasks"
```

**PowerShell:**

```powershell
. .\aws-ids.ps1

# Crear archivos de containers
$vms = @("db01", "api01", "frontend01", "frontend02", "lb01")
foreach ($vm in $vms) {
    @"
{
  "Description": "CloudCuyo $vm",
  "Format": "ova",
  "UserBucket": {
    "S3Bucket": "$BucketName",
    "S3Key": "cloudcuyo-${vm}.ova"
  }
}
"@ | Out-File -FilePath "${vm}-containers.json" -Encoding UTF8
}

# Importar VMs
$DbImport = (Import-EC2Image -Description "CloudCuyo DB01" -DiskContainer (Get-Content "db01-containers.json" | ConvertFrom-Json)).ImportTaskId
$ApiImport = (Import-EC2Image -Description "CloudCuyo API01" -DiskContainer (Get-Content "api01-containers.json" | ConvertFrom-Json)).ImportTaskId
$Front01Import = (Import-EC2Image -Description "CloudCuyo Frontend01" -DiskContainer (Get-Content "frontend01-containers.json" | ConvertFrom-Json)).ImportTaskId
$Front02Import = (Import-EC2Image -Description "CloudCuyo Frontend02" -DiskContainer (Get-Content "frontend02-containers.json" | ConvertFrom-Json)).ImportTaskId
$LbImport = (Import-EC2Image -Description "CloudCuyo LB01" -DiskContainer (Get-Content "lb01-containers.json" | ConvertFrom-Json)).ImportTaskId

Write-Host "Tasks de importacion iniciadas"
```



---

## Fase 5: Lanzar instancias EC2

### 5.1. Obtener Instance Profile para SSM

El stack de CloudFormation creó un Instance Profile que **TODAS** las instancias deben usar:

**Bash:**

```bash
source aws-ids.sh

# Obtener nombre del Instance Profile del stack NAT
SSM_PROFILE_NAME=$(aws cloudformation describe-stacks --stack-name cloudcuyo-nat-instance --query 'Stacks[0].Outputs[?OutputKey==`SSMInstanceProfileName`].OutputValue' --output text)

echo "SSM Instance Profile: $SSM_PROFILE_NAME"
echo "export SSM_PROFILE_NAME=$SSM_PROFILE_NAME" >> aws-ids.sh
```

**PowerShell:**

```powershell
. .\aws-ids.ps1

$Stack = Get-CFNStack -StackName "cloudcuyo-nat-instance"
$SsmProfileName = ($Stack.Outputs | Where-Object { $_.OutputKey -eq "SSMInstanceProfileName" }).OutputValue

Write-Host "SSM Instance Profile: $SsmProfileName" -ForegroundColor Green
"`$SsmProfileName = `"$SsmProfileName`"" | Add-Content -Path "aws-ids.ps1"
```

### 5.2. Lanzar DB01 (primero, es crítica)

**Bash:**

```bash
source aws-ids.sh

# Crear Security Group para DB
DB_SG=$(aws ec2 create-security-group --group-name cloudcuyo-db-sg --description "Security group for DB instance" --vpc-id $VPC_ID --query 'GroupId' --output text)

# Permitir PostgreSQL desde subnet privada
aws ec2 authorize-security-group-ingress --group-id $DB_SG --protocol tcp --port 5432 --cidr 10.0.0.0/16
# HTTPS para SSM
aws ec2 authorize-security-group-ingress --group-id $DB_SG --protocol tcp --port 443 --cidr 10.0.0.0/16

# Lanzar DB01
DB_INSTANCE=$(aws ec2 run-instances --image-id $DB_AMI --instance-type t3.medium --key-name cloudcuyo-key --security-group-ids $DB_SG --subnet-id $PRIVATE_SUBNET_ID --private-ip-address 10.0.2.40 --iam-instance-profile Name=$SSM_PROFILE_NAME --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=cloudcuyo-db01},{Key=Role,Value=database}]' --query 'Instances[0].InstanceId' --output text)

echo "✓ DB01 lanzada: $DB_INSTANCE"
aws ec2 wait instance-running --instance-ids $DB_INSTANCE
echo "✓ DB01 corriendo"
```

**PowerShell:**

```powershell
. .\aws-ids.ps1

# Security Group para DB
$DbSg = New-EC2SecurityGroup -GroupName "cloudcuyo-db-sg" -Description "Security group for DB instance" -VpcId $VpcId

# Reglas
Grant-EC2SecurityGroupIngress -GroupId $DbSg -IpPermission @(
    @{ IpProtocol="tcp"; FromPort=5432; ToPort=5432; IpRanges="10.0.0.0/16" }
    @{ IpProtocol="tcp"; FromPort=443; ToPort=443; IpRanges="10.0.0.0/16" }
)

# Lanzar DB01
$DbInstance = (New-EC2Instance -ImageId $DbAmi -InstanceType "t3.medium" -KeyName "cloudcuyo-key" -SecurityGroupId $DbSg -SubnetId $PrivateSubnetId -PrivateIpAddress "10.0.2.40" -IamInstanceProfile_Name $SsmProfileName -TagSpecification @{ ResourceType="instance"; Tags=@( @{Key="Name";Value="cloudcuyo-db01"}, @{Key="Role";Value="database"} ) }).Instances[0].InstanceId

Write-Host "✓ DB01 lanzada: $DbInstance" -ForegroundColor Green
Wait-EC2InstanceRunning -InstanceId $DbInstance
Write-Host "✓ DB01 corriendo" -ForegroundColor Green
```

### 5.3. Lanzar resto de instancias

**Bash:**

```bash
# API01
API_SG=$(aws ec2 create-security-group --group-name cloudcuyo-api-sg --description "API SG" --vpc-id $VPC_ID --query 'GroupId' --output text)
aws ec2 authorize-security-group-ingress --group-id $API_SG --protocol tcp --port 5000 --cidr 10.0.0.0/16
aws ec2 authorize-security-group-ingress --group-id $API_SG --protocol tcp --port 443 --cidr 10.0.0.0/16

API_INSTANCE=$(aws ec2 run-instances --image-id $API_AMI --instance-type t3.small --key-name cloudcuyo-key --security-group-ids $API_SG --subnet-id $PRIVATE_SUBNET_ID --private-ip-address 10.0.2.30 --iam-instance-profile Name=$SSM_PROFILE_NAME --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=cloudcuyo-api01}]' --query 'Instances[0].InstanceId' --output text)

# Frontend01
FRONT_SG=$(aws ec2 create-security-group --group-name cloudcuyo-frontend-sg --description "Frontend SG" --vpc-id $VPC_ID --query 'GroupId' --output text)
aws ec2 authorize-security-group-ingress --group-id $FRONT_SG --protocol tcp --port 80 --cidr 0.0.0.0/0
aws ec2 authorize-security-group-ingress --group-id $FRONT_SG --protocol tcp --port 443 --cidr 0.0.0.0/0

FRONT01_INSTANCE=$(aws ec2 run-instances --image-id $FRONT01_AMI --instance-type t3.micro --key-name cloudcuyo-key --security-group-ids $FRONT_SG --subnet-id $PUBLIC_SUBNET_ID --iam-instance-profile Name=$SSM_PROFILE_NAME --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=cloudcuyo-frontend01}]' --query 'Instances[0].InstanceId' --output text)

# Frontend02
FRONT02_INSTANCE=$(aws ec2 run-instances --image-id $FRONT02_AMI --instance-type t3.micro --key-name cloudcuyo-key --security-group-ids $FRONT_SG --subnet-id $PUBLIC_SUBNET_ID --iam-instance-profile Name=$SSM_PROFILE_NAME --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=cloudcuyo-frontend02}]' --query 'Instances[0].InstanceId' --output text)

# LB01
LB_SG=$(aws ec2 create-security-group --group-name cloudcuyo-lb-sg --description "LB SG" --vpc-id $VPC_ID --query 'GroupId' --output text)
aws ec2 authorize-security-group-ingress --group-id $LB_SG --protocol tcp --port 80 --cidr 0.0.0.0/0

LB_INSTANCE=$(aws ec2 run-instances --image-id $LB_AMI --instance-type t3.micro --key-name cloudcuyo-key --security-group-ids $LB_SG --subnet-id $PUBLIC_SUBNET_ID --iam-instance-profile Name=$SSM_PROFILE_NAME --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=cloudcuyo-lb01}]' --query 'Instances[0].InstanceId' --output text)

echo "✓ Todas las instancias lanzadas"
aws ec2 wait instance-running --instance-ids $API_INSTANCE $FRONT01_INSTANCE $FRONT02_INSTANCE $LB_INSTANCE

# Obtener IP pública del LB
LB_PUBLIC_IP=$(aws ec2 describe-instances --instance-ids $LB_INSTANCE --query 'Reservations[0].Instances[0].PublicIpAddress' --output text)

echo ""
echo "========================================="
echo "✓ CloudCuyo migrado a AWS"
echo "Acceso: http://$LB_PUBLIC_IP"
echo "========================================="
```

**PowerShell:**

```powershell
# API01
$ApiSg = New-EC2SecurityGroup -GroupName "cloudcuyo-api-sg" -Description "API SG" -VpcId $VpcId
Grant-EC2SecurityGroupIngress -GroupId $ApiSg -IpProtocol tcp -FromPort 5000 -ToPort 5000 -CidrIp "10.0.0.0/16"
Grant-EC2SecurityGroupIngress -GroupId $ApiSg -IpProtocol tcp -FromPort 443 -ToPort 443 -CidrIp "10.0.0.0/16"

$ApiInstance = (New-EC2Instance -ImageId $ApiAmi -InstanceType t3.small -KeyName "cloudcuyo-key" -SecurityGroupId $ApiSg -SubnetId $PrivateSubnetId -PrivateIpAddress "10.0.2.30" -IamInstanceProfile_Name $SsmProfileName -TagSpecification @( @{ ResourceType = "instance"; Tags = @( @{ Key = "Name"; Value = "cloudcuyo-api01" } ) } )).Instances[0].InstanceId

# Frontend01
$FrontSg = New-EC2SecurityGroup -GroupName "cloudcuyo-frontend-sg" -Description "Frontend SG" -VpcId $VpcId
Grant-EC2SecurityGroupIngress -GroupId $FrontSg -IpProtocol tcp -FromPort 80 -ToPort 80 -CidrIp "0.0.0.0/0"
Grant-EC2SecurityGroupIngress -GroupId $FrontSg -IpProtocol tcp -FromPort 443 -ToPort 443 -CidrIp "0.0.0.0/0"

$Front01Instance = (New-EC2Instance -ImageId $Front01Ami -InstanceType t3.micro -KeyName "cloudcuyo-key" -SecurityGroupId $FrontSg -SubnetId $PublicSubnetId -IamInstanceProfile_Name $SsmProfileName -TagSpecification @( @{ ResourceType = "instance"; Tags = @( @{ Key = "Name"; Value = "cloudcuyo-frontend01" } ) } )).Instances[0].InstanceId

# Frontend02
$Front02Instance = (New-EC2Instance -ImageId $Front02Ami -InstanceType t3.micro -KeyName "cloudcuyo-key" -SecurityGroupId $FrontSg -SubnetId $PublicSubnetId -IamInstanceProfile_Name $SsmProfileName -TagSpecification @( @{ ResourceType = "instance"; Tags = @( @{ Key = "Name"; Value = "cloudcuyo-frontend02" } ) } )).Instances[0].InstanceId

# LB01
$LbSg = New-EC2SecurityGroup -GroupName "cloudcuyo-lb-sg" -Description "LB SG" -VpcId $VpcId
Grant-EC2SecurityGroupIngress -GroupId $LbSg -IpProtocol tcp -FromPort 80 -ToPort 80 -CidrIp "0.0.0.0/0"

$LbInstance = (New-EC2Instance -ImageId $LbAmi -InstanceType t3.micro -KeyName "cloudcuyo-key" -SecurityGroupId $LbSg -SubnetId $PublicSubnetId -IamInstanceProfile_Name $SsmProfileName -TagSpecification @( @{ ResourceType = "instance"; Tags = @( @{ Key = "Name"; Value = "cloudcuyo-lb01" } ) } )).Instances[0].InstanceId

Write-Host "✓ Todas las instancias lanzadas" -ForegroundColor Green

# Esperar a que corran
Wait-EC2InstanceRunning -InstanceId @($ApiInstance, $Front01Instance, $Front02Instance, $LbInstance)

# Obtener IP pública del LB
$LbPublicIp = (Get-EC2Instance -InstanceId $LbInstance).Instances[0].PublicIpAddress

Write-Host ""
Write-Host "=========================================" -ForegroundColor Green
Write-Host "✓ CloudCuyo migrado a AWS"
Write-Host "Acceso: http://$LbPublicIp"
Write-Host "=========================================" -ForegroundColor Green
```

---

## Fase 6: Verificación y administración via SSM

### 6.1. Conectar via Session Manager

**Bash:**

```bash
# Ver instancias disponibles
aws ssm describe-instance-information --output table

# Conectar a DB01 (privada, sin IP pública)
aws ssm start-session --target $DB_INSTANCE

# Dentro de la sesión:
# sudo su -
# systemctl status postgresql
# psql -U cloudcuyo -d cloudcuyo
```

**PowerShell:**

```powershell
# Ver instancias disponibles
Get-SSMInstanceInformation | Format-Table InstanceId, PingStatus, PlatformName

# Conectar a DB01
Start-SSMSession -Target $DbInstance

# Ejecutar comando remoto sin sesión interactiva
Send-SSMCommand -InstanceId $DbInstance -DocumentName "AWS-RunShellScript" -Parameter @{ commands = @( "sudo systemctl status postgresql", "sudo -u postgres psql -d cloudcuyo -c 'SELECT count(*) FROM customers;'" ) }
```

### 6.2. Verificar conectividad

**Bash:**

```bash
# Health check
curl http://$LB_PUBLIC_IP/api/health

# Portal
curl -I http://$LB_PUBLIC_IP/portal.html

# API pública
curl http://$LB_PUBLIC_IP/api/v1/health
```

**PowerShell:**

```powershell
# Health check
Invoke-WebRequest -Uri "http://$LbPublicIp/api/health" | Select-Object -Expand Content

# Portal
Invoke-WebRequest -Uri "http://$LbPublicIp/portal.html" -Method Head

# API pública
Invoke-RestMethod -Uri "http://$LbPublicIp/api/v1/health"
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
| Elastic IPs        | 2 (NAT + LB) | ~$7                   |
| EBS (5 instancias) | ~50GB total  | ~$5                   |
| Data Transfer      | ~10GB/mes    | ~$1                   |
| **TOTAL**          |              | **~$87/mes**          |


---

## Limpieza

**Bash:**

```bash
source aws-ids.sh

# Terminar instancias
aws ec2 terminate-instances --instance-ids $DB_INSTANCE $API_INSTANCE $FRONT01_INSTANCE $FRONT02_INSTANCE $LB_INSTANCE

# Eliminar CloudFormation stack (NAT instance)
aws cloudformation delete-stack --stack-name cloudcuyo-nat-instance

# Limpiar S3
aws s3 rm s3://${BUCKET_NAME} --recursive
aws s3 rb s3://${BUCKET_NAME}

# Eliminar VPC (después de que todo esté terminado)
# aws ec2 delete-vpc --vpc-id $VPC_ID
```

**PowerShell:**

```powershell
. .\aws-ids.ps1

# Terminar instancias
Remove-EC2Instance -InstanceId @($DbInstance, $ApiInstance, $Front01Instance, $Front02Instance, $LbInstance) -Force

# Eliminar stack
Remove-CFNStack -StackName "cloudcuyo-nat-instance" -Force

# Limpiar S3
Remove-S3Object -BucketName $BucketName -KeyPrefix "" -Force
Remove-S3Bucket -BucketName $BucketName -Force
```

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

