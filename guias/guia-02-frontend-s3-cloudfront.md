# Guia 2: REPLATFORM Frontend - S3 + CloudFront

**Objetivo:** Migrar el frontend estático de CloudCuyo desde instancias EC2 a S3 + CloudFront, optimizando costos y performance.

**Duración estimada:** 2-3 horas

**Estrategia 6R:** **REPLATFORM** (Re-arquitecturar para la plataforma cloud)

---

## Contexto

Después del REHOST exitoso (Lab 1), CloudCuyo identifica oportunidades de optimización:

**Problema actual:**
- 2 instancias EC2 sirviendo contenido estático (~$15/mes)
- Mantenimiento manual de NGINX
- Sin CDN global
- Escalabilidad limitada

**Solución:**
- Frontend estático → S3
- Distribución global → CloudFront
- Reducción de costos ~94% ($15 → $0.92/mes)
- Performance mejorado globalmente
- Zero mantenimiento

---

## Arquitectura objetivo

```
┌──────────────────────────────────────────────┐
│  CloudFront Distribution                     │
│  (CDN Global - 200+ edge locations)          │
│  https://d1234567890.cloudfront.net          │
└────┬─────────────────────────────────────────┘
     │
     ├─► Origin 1: S3 Bucket (default)
     │   - index.html, portal.html
     │   - assets/css/*, assets/js/*
     │
     └─► Origin 2: ALB/EC2 (path /api/*)
         - Proxy inverso para APIs
         - Mantiene backend sin cambios
```

---

## Pre-requisitos

- Lab 1 completado (infraestructura en AWS EC2)
- Acceso a AWS Console
- IP pública del Load Balancer (LB01)

### Obtener IP del Load Balancer

**Usando AWS Console:**

1. Ir a **EC2** > **Instances**
2. Buscar la instancia con nombre `cloudcuyo-lb01`
3. En la pestaña **Details**, copiar el valor de **Public IPv4 address**
4. **Anotar esta IP** (la necesitarás más adelante)

<details>
<summary><b>Alternativa: Usando CLI (Bash/PowerShell)</b></summary>

**Bash:**
```bash
# Si no tienes la IP, obtenerla:
LB_PUBLIC_IP=$(aws ec2 describe-instances --filters "Name=tag:Name,Values=cloudcuyo-lb01" --query 'Reservations[0].Instances[0].PublicIpAddress' --output text)

echo "LB IP: $LB_PUBLIC_IP"
```

**PowerShell:**
```powershell
# Obtener IP del LB
$LbPublicIp = (Get-EC2Instance -Filter @{Name="tag:Name";Values="cloudcuyo-lb01"}).Instances[0].PublicIpAddress

Write-Host "LB IP: $LbPublicIp"
```

</details>

---

## Fase 1: Crear y configurar S3 Bucket

### 1.1. Crear bucket S3

**Usando AWS Console:**

1. Ir a **S3** en la consola de AWS
2. Click en **Create bucket**
3. Configurar:
   - **Bucket name:** `cloudcuyo-frontend-<tu-numero-unico>` (ej: `cloudcuyo-frontend-20260513`)
   - **AWS Region:** `us-east-1`
   - **Block Public Access settings:** Dejar todo marcado (CloudFront accederá via OAI)
   - **Bucket Versioning:** Enable
   - Resto de opciones: dejar por defecto
4. Click **Create bucket**
5. **Anotar el nombre exacto del bucket**

<details>
<summary><b>Alternativa: Usando CLI (Bash/PowerShell)</b></summary>

**Bash:**
```bash
BUCKET_NAME="cloudcuyo-frontend-$(date +%s)"
AWS_REGION="us-east-1"

aws s3 mb s3://${BUCKET_NAME} --region ${AWS_REGION}

# Habilitar versionado
aws s3api put-bucket-versioning --bucket ${BUCKET_NAME} --versioning-configuration Status=Enabled

# Block public access (CloudFront usará OAI)
aws s3api put-public-access-block --bucket ${BUCKET_NAME} --public-access-block-configuration BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true

echo "Bucket creado: $BUCKET_NAME"
echo "export BUCKET_NAME=$BUCKET_NAME" >> cloudfront-vars.sh
```

**PowerShell:**
```powershell
$BucketName = "cloudcuyo-frontend-$(Get-Date -Format 'yyyyMMddHHmmss')"
$Region = "us-east-1"

Set-DefaultAWSRegion -Region $Region

New-S3Bucket -BucketName $BucketName -Region $Region

# Habilitar versionado
Write-S3BucketVersioning -BucketName $BucketName -VersioningConfig_Status Enabled

# Block public access
Add-S3PublicAccessBlock -BucketName $BucketName -PublicAccessBlockConfiguration_BlockPublicAcl $true -PublicAccessBlockConfiguration_IgnorePublicAcl $true -PublicAccessBlockConfiguration_BlockPublicPolicy $true -PublicAccessBlockConfiguration_RestrictPublicBucket $true

Write-Host "Bucket creado: $BucketName" -ForegroundColor Green
"`$BucketName = `"$BucketName`"" | Out-File -FilePath "cloudfront-vars.ps1"
```

</details>

---

## Fase 2: Preparar y subir archivos

### 2.1. Actualizar configuración de API en JavaScript

Los archivos JS necesitan usar rutas relativas para que CloudFront haga proxy a la API backend.

**Editar localmente `app/frontend/assets/js/main.js` y `portal.js`:**

```javascript
// Cambiar de:
// const API_BASE = 'http://192.168.56.10/api';

// A:
const API_BASE = window.location.hostname === 'localhost' 
  ? 'http://192.168.56.10/api'
  : '/api';  // Relativo, CloudFront hará proxy
```

### 2.2. Subir archivos al bucket S3

**Usando AWS Console:**

1. Ir a **S3** > Tu bucket `cloudcuyo-frontend-...`
2. Click en **Upload**
3. Click en **Add files** o arrastra la carpeta `app/frontend/` completa
4. Asegurarte de incluir:
   - `index.html`
   - `portal.html`
   - `clientes.html`
   - `contacto.html`
   - `hosting.html`
   - `soluciones.html`
   - Carpeta `assets/` (con subcarpetas `css/` y `js/`)
5. Click **Upload**
6. Esperar a que termine

**Configurar metadata de archivos (importante para Content-Type):**

Por defecto, S3 detecta automáticamente el Content-Type. Si tienes problemas:
1. Seleccionar archivos `.html`
2. **Actions** > **Edit metadata**
3. **Type:** `System-defined`
4. **Key:** `Content-Type`, **Value:** `text/html`
5. Repetir para `.css` (`text/css`) y `.js` (`application/javascript`)

<details>
<summary><b>Alternativa: Usando CLI (Bash/PowerShell)</b></summary>

**Bash:**
```bash
source cloudfront-vars.sh

cd app/frontend

# Subir todo el contenido
aws s3 sync . s3://${BUCKET_NAME}/ --exclude "*.md" --exclude ".git*" --delete

# Configurar content-types correctos
aws s3 cp s3://${BUCKET_NAME}/assets/css/ s3://${BUCKET_NAME}/assets/css/ --recursive --content-type "text/css" --metadata-directive REPLACE

aws s3 cp s3://${BUCKET_NAME}/assets/js/ s3://${BUCKET_NAME}/assets/js/ --recursive --content-type "application/javascript" --metadata-directive REPLACE

aws s3 cp s3://${BUCKET_NAME}/ s3://${BUCKET_NAME}/ --recursive --exclude "*" --include "*.html" --content-type "text/html" --metadata-directive REPLACE

# Cache headers
# HTML: cache corto
aws s3 cp s3://${BUCKET_NAME}/ s3://${BUCKET_NAME}/ --recursive --exclude "*" --include "*.html" --cache-control "max-age=300, must-revalidate" --metadata-directive REPLACE

# CSS/JS: cache largo
aws s3 cp s3://${BUCKET_NAME}/assets/ s3://${BUCKET_NAME}/assets/ --recursive --cache-control "max-age=31536000, immutable" --metadata-directive REPLACE

echo "✓ Archivos subidos a S3"
aws s3 ls s3://${BUCKET_NAME}/ --recursive --human-readable
```

**PowerShell:**
```powershell
. .\cloudfront-vars.ps1

Set-Location "app\frontend"

# Subir archivos
Write-S3Object -BucketName $BucketName -Folder . -KeyPrefix "" -Recurse

# Configurar content-types (PowerShell requiere hacerlo por archivo)
$cssFiles = Get-S3Object -BucketName $BucketName -KeyPrefix "assets/css/"
foreach ($file in $cssFiles) {
    Copy-S3Object -BucketName $BucketName -Key $file.Key -DestinationBucket $BucketName -DestinationKey $file.Key -ContentType "text/css" -MetadataDirective REPLACE
}

$jsFiles = Get-S3Object -BucketName $BucketName -KeyPrefix "assets/js/"
foreach ($file in $jsFiles) {
    Copy-S3Object -BucketName $BucketName -Key $file.Key -DestinationBucket $BucketName -DestinationKey $file.Key -ContentType "application/javascript" -MetadataDirective REPLACE
}

Write-Host "✓ Archivos subidos a S3" -ForegroundColor Green
Get-S3Object -BucketName $BucketName | Format-Table Key, Size
```

</details>

---

## Fase 3: Configurar CORS en API Backend

Para que el frontend en CloudFront pueda hacer peticiones a la API, necesitamos habilitar CORS.

**Usando AWS Console (Systems Manager):**

1. Ir a **Systems Manager** > **Fleet Manager** (o **Session Manager**)
2. Click en **Start session**
3. Seleccionar la instancia `cloudcuyo-api01`
4. Click **Start session**
5. En la terminal, ejecutar:
   ```bash
   sudo sed -i 's/CORS(app)/CORS(app, resources={r"\/api\/*": {"origins": "*"}})/g' /opt/cloudcuyo-api/app.py
   sudo systemctl restart cloudcuyo-api
   sudo systemctl status cloudcuyo-api
   ```
6. Verificar que el servicio esté **active (running)**
7. Cerrar la sesión

<details>
<summary><b>Alternativa: Usando CLI (Bash/PowerShell)</b></summary>

**Bash:**
```bash
# Conectar via SSM a la instancia de API
API_INSTANCE=$(aws ec2 describe-instances --filters "Name=tag:Name,Values=cloudcuyo-api01" --query 'Reservations[0].Instances[0].InstanceId' --output text)

# Actualizar CORS
aws ssm send-command --instance-ids $API_INSTANCE --document-name "AWS-RunShellScript" --parameters 'commands=["sudo sed -i \"s/CORS(app)/CORS(app, resources={r\\\"\/api\/*\\\": {\\\"origins\\\": \\\"*\\\"}})/\" /opt/cloudcuyo-api/app.py","sudo systemctl restart cloudcuyo-api","sudo systemctl status cloudcuyo-api"]'
```

**PowerShell:**
```powershell
$ApiInstance = (Get-EC2Instance -Filter @{Name="tag:Name";Values="cloudcuyo-api01"}).Instances[0].InstanceId

Send-SSMCommand -InstanceId $ApiInstance -DocumentName "AWS-RunShellScript" -Parameter @{ commands = @( 'sudo sed -i "s/CORS(app)/CORS(app, resources={r\"\/api\/*\": {\"origins\": \"*\"}})/g" /opt/cloudcuyo-api/app.py', "sudo systemctl restart cloudcuyo-api" ) }
```

</details>

---

## Fase 4: Crear CloudFront Distribution

### 4.1. Crear Origin Access Control (OAC)

**Usando AWS Console:**

1. Ir a **CloudFront** en la consola de AWS
2. En el menu lateral, ir a **Origin access** > **Origin access control**
3. Click en **Create control setting**
4. Configurar:
   - **Name:** `cloudcuyo-oac`
   - **Description:** `CloudCuyo S3 Origin Access Control`
   - **Signing behavior:** `Sign requests (recommended)`
   - **Origin type:** `S3`
5. Click **Create**
6. **Anotar el ID del OAC** (lo necesitarás para la bucket policy)

<details>
<summary><b>Alternativa: Crear Origin Access Identity (OAI) - método legacy</b></summary>

**Bash:**
```bash
OAI_ID=$(aws cloudfront create-cloud-front-origin-access-identity --cloud-front-origin-access-identity-config CallerReference="cloudcuyo-oai-$(date +%s)",Comment="CloudCuyo S3 OAI" --query 'CloudFrontOriginAccessIdentity.Id' --output text)

echo "OAI ID: $OAI_ID"
echo "export OAI_ID=$OAI_ID" >> cloudfront-vars.sh
```

**PowerShell:**
```powershell
$OaiConfig = @{
    CallerReference = "cloudcuyo-oai-$(Get-Date -Format 'yyyyMMddHHmmss')"
    Comment = "CloudCuyo S3 OAI"
}

$Oai = New-CFOriginAccessIdentity -CloudFrontOriginAccessIdentityConfig $OaiConfig
$OaiId = $Oai.Id

Write-Host "OAI ID: $OaiId" -ForegroundColor Green
"`$OaiId = `"$OaiId`"" | Add-Content -Path "cloudfront-vars.ps1"
```

</details>

### 4.2. Crear CloudFront Distribution

**Usando AWS Console:**

1. Ir a **CloudFront** > **Distributions**
2. Click en **Create distribution**
3. **Origin settings:**
   - **Origin domain:** Seleccionar tu bucket S3 `cloudcuyo-frontend-...`
   - **Origin access:** `Origin access control settings (recommended)`
   - **Origin access control:** Seleccionar el OAC creado (`cloudcuyo-oac`)
   - **Name:** Dejar el nombre generado automáticamente
4. **Default cache behavior:**
   - **Viewer protocol policy:** `Redirect HTTP to HTTPS`
   - **Allowed HTTP methods:** `GET, HEAD`
   - **Compress objects automatically:** `Yes`
   - Resto: dejar por defecto
5. **Settings:**
   - **Price class:** `Use only North America and Europe`
   - **Default root object:** `index.html`
6. Click **Create distribution**
7. **IMPORTANTE:** Aparecerá un banner azul diciendo "The S3 bucket policy needs to be updated". Click en **Copy policy** y continúa con el paso 4.3

**Anotar:**
- **Distribution domain name** (ej: `d1234567890.cloudfront.net`)
- **Distribution ID** (ej: `E1234567890ABC`)

### 4.3. Actualizar bucket policy

**Usando AWS Console:**

1. Copiar la política que apareció en el banner (paso anterior)
2. Ir a **S3** > Tu bucket `cloudcuyo-frontend-...`
3. Ir a la pestaña **Permissions**
4. En **Bucket policy**, click **Edit**
5. Pegar la política copiada (o usar esta plantilla, reemplazando valores):
   ```json
   {
     "Version": "2012-10-17",
     "Statement": [{
       "Sid": "AllowCloudFrontServicePrincipal",
       "Effect": "Allow",
       "Principal": {
         "Service": "cloudfront.amazonaws.com"
       },
       "Action": "s3:GetObject",
       "Resource": "arn:aws:s3:::cloudcuyo-frontend-<tu-numero>/*",
       "Condition": {
         "StringEquals": {
           "AWS:SourceArn": "arn:aws:cloudfront::<tu-account-id>:distribution/<distribution-id>"
         }
       }
     }]
   }
   ```
6. Click **Save changes**

<details>
<summary><b>Alternativa: Usando CLI (Bash/PowerShell)</b></summary>

**Bash:**
```bash
source cloudfront-vars.sh

cat > bucket-policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": {
      "AWS": "arn:aws:iam::cloudfront:user/CloudFront Origin Access Identity ${OAI_ID}"
    },
    "Action": "s3:GetObject",
    "Resource": "arn:aws:s3:::${BUCKET_NAME}/*"
  }]
}
EOF

aws s3api put-bucket-policy --bucket ${BUCKET_NAME} --policy file://bucket-policy.json
echo "✓ Bucket policy actualizada"
```

**PowerShell:**
```powershell
. .\cloudfront-vars.ps1

$BucketPolicy = @"
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": {
      "AWS": "arn:aws:iam::cloudfront:user/CloudFront Origin Access Identity $OaiId"
    },
    "Action": "s3:GetObject",
    "Resource": "arn:aws:s3:::$BucketName/*"
  }]
}
"@

Write-S3BucketPolicy -BucketName $BucketName -Policy $BucketPolicy
Write-Host "✓ Bucket policy actualizada" -ForegroundColor Green
```

</details>

### 4.4. Agregar origen de API (Backend)

**Usando AWS Console:**

1. Ir a **CloudFront** > **Distributions**
2. Click en tu distribución (domain name `d1234567890.cloudfront.net`)
3. Ir a la pestaña **Origins**
4. Click en **Create origin**
5. Configurar:
   - **Origin domain:** Pegar la IP pública del LB (NO seleccionar de la lista, escribir manualmente)
   - **Protocol:** `HTTP only`
   - **HTTP port:** `80`
   - **Origin path:** Dejar vacío
   - **Name:** `EC2-API-Backend`
6. Click **Create origin**

### 4.5. Configurar cache behavior para /api/*

**Usando AWS Console:**

1. En la misma distribución, ir a la pestaña **Behaviors**
2. Click en **Create behavior**
3. Configurar:
   - **Path pattern:** `/api/*`
   - **Origin and origin groups:** Seleccionar `EC2-API-Backend`
   - **Viewer protocol policy:** `HTTP and HTTPS`
   - **Allowed HTTP methods:** `GET, HEAD, OPTIONS, PUT, POST, PATCH, DELETE`
   - **Cache policy:** `CachingDisabled` (buscar en la lista)
   - **Origin request policy:** `AllViewer` (buscar en la lista)
4. Click **Create behavior**

### 4.6. Configurar página de error 404

**Usando AWS Console:**

1. En la distribución, ir a la pestaña **Error pages**
2. Click en **Create custom error response**
3. Configurar:
   - **HTTP error code:** `404: Not Found`
   - **Customize error response:** `Yes`
   - **Response page path:** `/index.html`
   - **HTTP response code:** `200: OK`
4. Click **Create custom error response**

### 4.7. Esperar despliegue

El despliegue de CloudFront toma ~15-20 minutos.

**Monitorear estado:**
1. En **CloudFront** > **Distributions**
2. Ver la columna **Status**
3. Esperar a que cambie de `Deploying` a `Enabled`

<details>
<summary><b>Alternativa: Crear distribución completa usando CLI (configuración JSON)</b></summary>

### 4.3. Crear distribución de CloudFront

**Bash:**
```bash
source cloudfront-vars.sh

cat > cloudfront-config.json <<EOF
{
  "CallerReference": "cloudcuyo-$(date +%s)",
  "Comment": "CloudCuyo Frontend Distribution",
  "Enabled": true,
  "DefaultRootObject": "index.html",
  "Origins": {
    "Quantity": 2,
    "Items": [
      {
        "Id": "S3-cloudcuyo-frontend",
        "DomainName": "${BUCKET_NAME}.s3.amazonaws.com",
        "S3OriginConfig": {
          "OriginAccessIdentity": "origin-access-identity/cloudfront/${OAI_ID}"
        }
      },
      {
        "Id": "EC2-API-Backend",
        "DomainName": "${LB_PUBLIC_IP}",
        "CustomOriginConfig": {
          "HTTPPort": 80,
          "HTTPSPort": 443,
          "OriginProtocolPolicy": "http-only"
        }
      }
    ]
  },
  "DefaultCacheBehavior": {
    "TargetOriginId": "S3-cloudcuyo-frontend",
    "ViewerProtocolPolicy": "redirect-to-https",
    "AllowedMethods": {
      "Quantity": 2,
      "Items": ["GET", "HEAD"],
      "CachedMethods": {
        "Quantity": 2,
        "Items": ["GET", "HEAD"]
      }
    },
    "Compress": true,
    "ForwardedValues": {
      "QueryString": false,
      "Cookies": {"Forward": "none"}
    },
    "MinTTL": 0,
    "DefaultTTL": 86400,
    "MaxTTL": 31536000
  },
  "CacheBehaviors": {
    "Quantity": 1,
    "Items": [{
      "PathPattern": "/api/*",
      "TargetOriginId": "EC2-API-Backend",
      "ViewerProtocolPolicy": "allow-all",
      "AllowedMethods": {
        "Quantity": 7,
        "Items": ["GET", "HEAD", "OPTIONS", "PUT", "POST", "PATCH", "DELETE"],
        "CachedMethods": {
          "Quantity": 2,
          "Items": ["GET", "HEAD"]
        }
      },
      "Compress": false,
      "ForwardedValues": {
        "QueryString": true,
        "Cookies": {"Forward": "all"},
        "Headers": {
          "Quantity": 4,
          "Items": ["Accept", "Content-Type", "Authorization", "Origin"]
        }
      },
      "MinTTL": 0,
      "DefaultTTL": 0,
      "MaxTTL": 0
    }]
  },
  "CustomErrorResponses": {
    "Quantity": 1,
    "Items": [{
      "ErrorCode": 404,
      "ResponsePagePath": "/index.html",
      "ResponseCode": "200",
      "ErrorCachingMinTTL": 300
    }]
  },
  "PriceClass": "PriceClass_100"
}
EOF

DISTRIBUTION_ID=$(aws cloudfront create-distribution --distribution-config file://cloudfront-config.json --query 'Distribution.Id' --output text)

CLOUDFRONT_DOMAIN=$(aws cloudfront get-distribution --id $DISTRIBUTION_ID --query 'Distribution.DomainName' --output text)

echo "Distribution ID: $DISTRIBUTION_ID"
echo "CloudFront Domain: https://${CLOUDFRONT_DOMAIN}"
echo "Esperando despliegue (~15-20 min)..."

# Guardar
cat >> cloudfront-vars.sh <<EOF
export DISTRIBUTION_ID="$DISTRIBUTION_ID"
export CLOUDFRONT_DOMAIN="$CLOUDFRONT_DOMAIN"
EOF
```

**PowerShell:**
```powershell
. .\cloudfront-vars.ps1

# Crear configuración (PowerShell requiere objeto estructurado)
$Origins = @(
    @{
        Id = "S3-cloudcuyo-frontend"
        DomainName = "$BucketName.s3.amazonaws.com"
        S3OriginConfig = @{
            OriginAccessIdentity = "origin-access-identity/cloudfront/$OaiId"
        }
    },
    @{
        Id = "EC2-API-Backend"
        DomainName = $LbPublicIp
        CustomOriginConfig = @{
            HTTPPort = 80
            HTTPSPort = 443
            OriginProtocolPolicy = "http-only"
        }
    }
)

$DefaultCacheBehavior = @{
    TargetOriginId = "S3-cloudcuyo-frontend"
    ViewerProtocolPolicy = "redirect-to-https"
    AllowedMethods = @{
        Quantity = 2
        Items = @("GET", "HEAD")
        CachedMethods = @{
            Quantity = 2
            Items = @("GET", "HEAD")
        }
    }
    Compress = $true
    ForwardedValues = @{
        QueryString = $false
        Cookies = @{ Forward = "none" }
    }
    MinTTL = 0
    DefaultTTL = 86400
    MaxTTL = 31536000
}

# Nota: La creación completa en PowerShell es verbosa
# Recomendación: usar AWS CLI desde PowerShell o plantilla JSON

$DistConfig = @{
    CallerReference = "cloudcuyo-$(Get-Date -Format 'yyyyMMddHHmmss')"
    Comment = "CloudCuyo Frontend"
    Enabled = $true
    DefaultRootObject = "index.html"
    # ... (resto de configuración)
}

# Alternativamente, usar AWS CLI desde PowerShell:
$DistributionId = aws cloudfront create-distribution --distribution-config file://cloudfront-config.json --query 'Distribution.Id' --output text

$CloudfrontDomain = aws cloudfront get-distribution --id $DistributionId --query 'Distribution.DomainName' --output text

Write-Host "Distribution ID: $DistributionId" -ForegroundColor Green
Write-Host "CloudFront Domain: https://$CloudfrontDomain" -ForegroundColor Green
Write-Host "Esperando despliegue (~15-20 min)..." -ForegroundColor Yellow
```

### 4.8. Monitorear despliegue (CLI)

**Bash:**
```bash
source cloudfront-vars.sh

while true; do
  STATUS=$(aws cloudfront get-distribution --id $DISTRIBUTION_ID --query 'Distribution.Status' --output text)
  echo "Status: $STATUS"
  
  if [ "$STATUS" == "Deployed" ]; then
    echo "✓ CloudFront desplegado"
    break
  fi
  
  sleep 30
done
```

**PowerShell:**
```powershell
. .\cloudfront-vars.ps1

while ($true) {
    $Status = aws cloudfront get-distribution --id $DistributionId --query 'Distribution.Status' --output text
    Write-Host "Status: $Status"
    
    if ($Status -eq "Deployed") {
        Write-Host "✓ CloudFront desplegado" -ForegroundColor Green
        break
    }
    
    Start-Sleep -Seconds 30
}
```

</details>

---

## Fase 5: Testing

### 5.1. Probar acceso

**Usando navegador web:**

1. Abrir el navegador
2. Ir a `https://<tu-cloudfront-domain>.cloudfront.net`
   - Ejemplo: `https://d1234567890.cloudfront.net`
3. Verificar que carga la página de inicio
4. Probar navegación:
   - `https://<domain>.cloudfront.net/portal.html`
   - `https://<domain>.cloudfront.net/clientes.html`
   - `https://<domain>.cloudfront.net/hosting.html`

**Probar API a través de CloudFront:**

Abrir la consola del navegador (F12 > Console) y ejecutar:
```javascript
fetch('https://<tu-cloudfront-domain>.cloudfront.net/api/health')
  .then(r => r.json())
  .then(console.log)
```

Deberías ver una respuesta JSON con el estado de la API.

<details>
<summary><b>Alternativa: Usando CLI (Bash/PowerShell)</b></summary>

**Bash:**
```bash
source cloudfront-vars.sh

echo "Testing CloudFront distribution..."

# Frontend
curl -I https://${CLOUDFRONT_DOMAIN}
curl -I https://${CLOUDFRONT_DOMAIN}/portal.html

# API a través de CloudFront
curl https://${CLOUDFRONT_DOMAIN}/api/health
curl https://${CLOUDFRONT_DOMAIN}/api/v1/health
```

**PowerShell:**
```powershell
. .\cloudfront-vars.ps1

Write-Host "Testing CloudFront distribution..." -ForegroundColor Cyan

# Frontend
Invoke-WebRequest -Uri "https://$CloudfrontDomain" -Method Head
Invoke-WebRequest -Uri "https://$CloudfrontDomain/portal.html" -Method Head

# API
Invoke-RestMethod -Uri "https://$CloudfrontDomain/api/health"
Invoke-RestMethod -Uri "https://$CloudfrontDomain/api/v1/health"
```

</details>

### 5.2. Probar portal completo

1. Abrir en navegador: `https://<tu-cloudfront-domain>.cloudfront.net/portal.html`
2. Login con:
   - **Código:** `CUST-2020-003`
   - **Email:** `lfernandez@techmza.com`
3. Verificar que carga la información del cliente correctamente

---

## Fase 6: Invalidar cache de CloudFront

Cuando actualices archivos en S3, necesitas invalidar el cache de CloudFront para que los cambios se reflejen inmediatamente.

**Usando AWS Console:**

1. Ir a **CloudFront** > **Distributions**
2. Seleccionar tu distribución
3. Ir a la pestaña **Invalidations**
4. Click en **Create invalidation**
5. **Object paths:** Ingresar `/*` (invalida todo) o paths específicos como `/index.html`
6. Click **Create invalidation**
7. Esperar ~1-2 minutos a que se complete

<details>
<summary><b>Alternativa: Usando CLI (Bash/PowerShell)</b></summary>

**Bash:**
```bash
aws cloudfront create-invalidation --distribution-id $DISTRIBUTION_ID --paths "/*"
```

**PowerShell:**
```powershell
New-CFInvalidation -DistributionId $DistributionId -InvalidationBatch_CallerReference "invalidate-$(Get-Date -Format 'yyyyMMddHHmmss')" -InvalidationBatch_Path "/*"
```

</details>

---

## Fase 7: Desmantelar EC2 Frontend (opcional)

Una vez verificado que CloudFront funciona correctamente, puedes detener las instancias EC2 de frontend para ahorrar costos.

**Usando AWS Console:**

1. Ir a **EC2** > **Instances**
2. Seleccionar las instancias:
   - `cloudcuyo-frontend01`
   - `cloudcuyo-frontend02`
3. Click en **Instance state** > **Stop instance**
4. Confirmar

**Nota:** Las instancias detenidas NO generan costo de compute, pero sí de almacenamiento EBS (~$0.50/mes). Para eliminar completamente, usar **Terminate instance**.

<details>
<summary><b>Alternativa: Usando CLI (Bash/PowerShell)</b></summary>

**Bash:**
```bash
# Detener instancias de frontend
FRONT01=$(aws ec2 describe-instances --filters "Name=tag:Name,Values=cloudcuyo-frontend01" --query 'Reservations[0].Instances[0].InstanceId' --output text)
FRONT02=$(aws ec2 describe-instances --filters "Name=tag:Name,Values=cloudcuyo-frontend02" --query 'Reservations[0].Instances[0].InstanceId' --output text)

aws ec2 stop-instances --instance-ids $FRONT01 $FRONT02
```

**PowerShell:**
```powershell
$Front01 = (Get-EC2Instance -Filter @{Name="tag:Name";Values="cloudcuyo-frontend01"}).Instances[0].InstanceId
$Front02 = (Get-EC2Instance -Filter @{Name="tag:Name";Values="cloudcuyo-frontend02"}).Instances[0].InstanceId

Stop-EC2Instance -InstanceId @($Front01, $Front02)
```

</details>

---

## Comparativa de costos

| Componente | Antes (EC2) | Después (S3+CF) | Ahorro |
|------------|-------------|-----------------|--------|
| Frontend EC2 x2 | $15/mes | $0 | 100% |
| S3 Storage (1GB) | - | $0.02 | - |
| CloudFront (10GB) | - | $0.85 | - |
| **Total** | **$15** | **$0.87** | **~94%** |

---

## Script de despliegue continuo

**Bash:**
```bash
#!/bin/bash
# deploy-frontend.sh

source cloudfront-vars.sh

echo "=== Deploying CloudCuyo Frontend ==="

# Sync a S3
aws s3 sync app/frontend/ s3://${BUCKET_NAME}/ --delete

# Invalidar CloudFront
aws cloudfront create-invalidation --distribution-id $DISTRIBUTION_ID --paths "/*"

echo "✓ Deployment completed"
```

**PowerShell:**
```powershell
# deploy-frontend.ps1

. .\cloudfront-vars.ps1

Write-Host "=== Deploying CloudCuyo Frontend ===" -ForegroundColor Cyan

# Sync a S3
Write-S3Object -BucketName $BucketName -Folder "app\frontend" -KeyPrefix "" -Recurse

# Invalidar CloudFront
New-CFInvalidation -DistributionId $DistributionId -InvalidationBatch_CallerReference "deploy-$(Get-Date -Format 'yyyyMMddHHmmss')" -InvalidationBatch_Path "/*"

Write-Host "✓ Deployment completed" -ForegroundColor Green
```

---

## Limpieza

Si deseas eliminar todos los recursos creados:

**Usando AWS Console:**

1. **Deshabilitar distribución de CloudFront:**
   - Ir a **CloudFront** > **Distributions**
   - Seleccionar tu distribución
   - Click en **Disable**
   - Esperar ~15 min a que se desactive
   - Luego click en **Delete**

2. **Eliminar bucket S3:**
   - Ir a **S3**
   - Seleccionar bucket `cloudcuyo-frontend-...`
   - Click en **Empty** (elimina contenido)
   - Confirmar
   - Click en **Delete** (elimina bucket)

<details>
<summary><b>Alternativa: Usando CLI (Bash/PowerShell)</b></summary>

**Bash:**
```bash
# Deshabilitar y eliminar distribución
aws cloudfront get-distribution-config --id $DISTRIBUTION_ID > dist-config.json
# Editar dist-config.json: cambiar "Enabled": false
# aws cloudfront update-distribution --id $DISTRIBUTION_ID --if-match <ETag> --distribution-config file://dist-config.json
# aws cloudfront delete-distribution --id $DISTRIBUTION_ID --if-match <ETag>

# Eliminar bucket
aws s3 rm s3://${BUCKET_NAME} --recursive
aws s3 rb s3://${BUCKET_NAME}
```

**PowerShell:**
```powershell
# Deshabilitar distribución (proceso manual)
# Remove-CFDistribution requiere ETag

# Eliminar bucket
Remove-S3Object -BucketName $BucketName -KeyPrefix "" -Force
Remove-S3Bucket -BucketName $BucketName -Force
```

</details>

---

## Próximos desafíos

Una vez completado este lab, has logrado:
- Migrar frontend estático a S3 (REPLATFORM)
- Implementar CDN global con CloudFront
- Reducir costos en ~94% ($15 → $0.87/mes)
- Mejorar performance con edge locations

**Próximos labs recomendados:**
- **Próximos desafíos:** Refactorizar API a Lambda + API Gateway, Migrar DB a RDS managed service
