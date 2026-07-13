# Guia LAB06: Backend remoto con S3 y DynamoDB

**Modulo:** M3 - Clase 1: Infrastructure as Code  
**Duracion estimada:** 120 minutos  
**Proyecto Terraform:** creado por el alumno durante el laboratorio  
**Nivel:** intermedio  

---

## 1. Contexto

Hasta ahora trabajaste con state local. Eso funciona para aprender, pero no alcanza para trabajo en equipo.

Si dos personas usan copias locales distintas del state, pueden aplicar cambios contradictorios. Un backend remoto permite guardar el state en un lugar compartido. DynamoDB agrega locking para evitar que dos ejecuciones modifiquen el mismo state al mismo tiempo.

La pregunta central es:

> Donde vive el state cuando la infraestructura la administra un equipo?

---

## 2. Objetivos de aprendizaje

Al finalizar el LAB06 vas a poder:

1. Explicar la diferencia entre state local y backend remoto.
2. Crear recursos de soporte para backend: bucket S3 y tabla DynamoDB.
3. Configurar un backend S3 en Terraform.
4. Inicializar Terraform con backend remoto.
5. Entender el rol del locking.
6. Reconocer riesgos de borrar o modificar el backend.
7. Limpiar recursos de laboratorio de forma segura.

---

## 3. Arquitectura objetivo

```text
Terraform CLI
      |
      | backend "s3"
      v
S3 Bucket de state
      |
      | locking
      v
DynamoDB Table

Proyecto Terraform
      |
      v
Recurso de prueba: S3 bucket
```

Hay dos grupos de recursos:

1. Recursos de backend: bucket de state y tabla de locks.
2. Recurso de prueba: bucket administrado por el proyecto que usa backend remoto.

---

## 4. Alcance del LAB06

### Incluido

- Creacion de backend con Terraform en una carpeta bootstrap.
- Configuracion de backend remoto en un proyecto separado.
- Uso de S3 para state.
- Uso de DynamoDB para locking.
- Validacion del state remoto.
- Limpieza guiada.

### No incluido todavia

- Workspaces.
- CI/CD.
- Politicas avanzadas de IAM.
- Versionado de modulos remotos.
- Import.

---

## 5. Pre-requisitos

Necesitas:

- AWS CLI configurado.
- Terraform instalado.
- Permisos para crear y borrar:
  - S3 buckets.
  - DynamoDB tables.
- Region de trabajo: `us-east-1`.

Validar identidad:

```powershell
aws sts get-caller-identity
```

Anotar el `Account` devuelto. Lo vas a usar para nombres unicos.

---

## 6. Crear estructura del laboratorio

Desde la raiz del repositorio:

```powershell
mkdir terraform/iac-lab06-backend
cd terraform/iac-lab06-backend
mkdir 01-backend-bootstrap
mkdir 02-app-con-backend
```

Estructura final:

```text
terraform/iac-lab06-backend/
  01-backend-bootstrap/
    versions.tf
    providers.tf
    variables.tf
    terraform.tfvars
    main.tf
    outputs.tf
    .gitignore
  02-app-con-backend/
    versions.tf
    backend.tf
    providers.tf
    variables.tf
    terraform.tfvars
    main.tf
    outputs.tf
    .gitignore
```

---

# Parte A: Crear backend de soporte

## 7. Entrar a bootstrap

```powershell
cd 01-backend-bootstrap
```

Crear `.gitignore`:

```powershell
New-Item .gitignore
```

Contenido:

```gitignore
.terraform/
*.tfstate
*.tfstate.*
terraform.tfvars
```

---

## 8. Crear archivos base del bootstrap

Crear `versions.tf`:

```powershell
New-Item versions.tf
```

Contenido:

```hcl
terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}
```

Crear `providers.tf`:

```powershell
New-Item providers.tf
```

Contenido:

```hcl
provider "aws" {
  region = var.aws_region
}
```

Crear `variables.tf`:

```powershell
New-Item variables.tf
```

Contenido:

```hcl
variable "aws_region" {
  description = "Region AWS para backend."
  type        = string
}

variable "state_bucket_name" {
  description = "Nombre del bucket S3 para guardar state."
  type        = string
}

variable "lock_table_name" {
  description = "Nombre de la tabla DynamoDB para locking."
  type        = string
}
```

Crear `terraform.tfvars`:

```powershell
New-Item terraform.tfvars
```

Contenido ejemplo:

```hcl
aws_region        = "us-east-1"
state_bucket_name = "tfstate-formatec-tu-account-id-tu-identidad"
lock_table_name   = "tflock-formatec-tu-identidad"
```

Cambiar:

- `tu-account-id` por el ID de cuenta que te devuelva AWS.
- `tu-identidad` por tus iniciales, apellido corto o identificador del grupo, en minusculas y sin espacios.

---

## 9. Crear backend de soporte

Crear `main.tf`:

```powershell
New-Item main.tf
```

Contenido:

```hcl
resource "aws_s3_bucket" "terraform_state" {
  bucket = var.state_bucket_name

  tags = {
    Name      = var.state_bucket_name
    Course    = "formatec"
    ManagedBy = "terraform"
    Purpose   = "terraform-state"
  }
}

resource "aws_s3_bucket_versioning" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_dynamodb_table" "terraform_locks" {
  name         = var.lock_table_name
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }

  tags = {
    Name      = var.lock_table_name
    Course    = "formatec"
    ManagedBy = "terraform"
    Purpose   = "terraform-locking"
  }
}
```

Crear `outputs.tf`:

```powershell
New-Item outputs.tf
```

Contenido:

```hcl
output "state_bucket_name" {
  description = "Bucket S3 para backend remoto."
  value       = aws_s3_bucket.terraform_state.bucket
}

output "lock_table_name" {
  description = "Tabla DynamoDB para locking."
  value       = aws_dynamodb_table.terraform_locks.name
}
```

---

## 10. Crear recursos de backend

Ejecutar:

```powershell
terraform init -backend=false
terraform fmt
terraform validate
terraform plan
```

Si el plan es correcto y tenes autorizacion:

```powershell
terraform apply
```

Confirmar con:

```text
yes
```

Guardar outputs:

```powershell
terraform output
```

Checkpoint:

- Que recurso guarda el state?
- Que recurso maneja locks?
- Por que el bucket de state debe tener acceso publico bloqueado?
- Por que conviene versionado en el bucket de state?

---

# Parte B: Usar backend remoto

## 11. Entrar al proyecto de aplicacion

Desde `01-backend-bootstrap`:

```powershell
cd ../02-app-con-backend
```

Crear `.gitignore`:

```powershell
New-Item .gitignore
```

Contenido:

```gitignore
.terraform/
*.tfstate
*.tfstate.*
terraform.tfvars
```

---

## 12. Crear archivos base de la app

Crear `versions.tf`:

```powershell
New-Item versions.tf
```

Contenido:

```hcl
terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}
```

Crear `backend.tf`:

```powershell
New-Item backend.tf
```

Contenido ejemplo:

```hcl
terraform {
  backend "s3" {
    bucket         = "tfstate-formatec-tu-account-id-tu-identidad"
    key            = "m3-c1/lab06/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "tflock-formatec-tu-identidad"
    encrypt        = true
  }
}
```

Cambiar `bucket` y `dynamodb_table` por los valores creados en la Parte A.

Importante: el bloque `backend` no usa variables normales. Por eso los valores se escriben directamente en `backend.tf` para este lab.

En versiones actuales de Terraform, `dynamodb_table` puede mostrar el warning `Deprecated Parameter`. El mecanismo sigue funcionando y se usa en este laboratorio para observar el locking con DynamoDB. Para proyectos nuevos, Terraform recomienda el locking nativo de S3 mediante `use_lockfile = true`; no mezcles ambos enfoques durante este ejercicio.

Crear `providers.tf`:

```powershell
New-Item providers.tf
```

Contenido:

```hcl
provider "aws" {
  region = var.aws_region
}
```

Crear `variables.tf`:

```powershell
New-Item variables.tf
```

Contenido:

```hcl
variable "aws_region" {
  description = "Region AWS."
  type        = string
}

variable "bucket_name" {
  description = "Nombre del bucket de prueba."
  type        = string
}
```

Crear `terraform.tfvars`:

```powershell
New-Item terraform.tfvars
```

Contenido ejemplo:

```hcl
aws_region  = "us-east-1"
bucket_name = "backend-lab-app-tu-account-id-tu-identidad"
```

Cambiar el nombre del bucket por uno unico.

---

## 13. Crear recurso de prueba

Crear `main.tf`:

```powershell
New-Item main.tf
```

Contenido:

```hcl
resource "aws_s3_bucket" "app" {
  bucket = var.bucket_name

  tags = {
    Course    = "formatec"
    Lab       = "m3-c1-lab06"
    ManagedBy = "terraform"
  }
}
```

Crear `outputs.tf`:

```powershell
New-Item outputs.tf
```

Contenido:

```hcl
output "app_bucket_name" {
  description = "Nombre del bucket de prueba."
  value       = aws_s3_bucket.app.bucket
}
```

---

## 14. Inicializar con backend remoto

Ejecutar:

```powershell
terraform init
```

Terraform debe inicializar el backend S3.

Luego:

```powershell
terraform fmt
terraform validate
terraform plan
```

Checkpoint:

- Que diferencia hay entre `terraform init -backend=false` y `terraform init`?
- Donde se va a guardar el state de este proyecto?
- Que tabla se usa para locking?

---

## 15. Crear recurso con state remoto

Si el plan es correcto y tenes autorizacion:

```powershell
terraform apply
```

Confirmar con:

```text
yes
```

Ver outputs:

```powershell
terraform output
```

Revisar archivos locales:

```powershell
Get-ChildItem
```

No deberias depender de un `terraform.tfstate` local como en labs anteriores. El state vive en S3.

---

## 16. Verificar state en S3

Desde la terminal:

```powershell
aws s3 ls s3://NOMBRE_BUCKET_STATE/m3-c1/lab06/
```

Reemplazar `NOMBRE_BUCKET_STATE` por el bucket de backend.

Esperado: ver un objeto similar a:

```text
terraform.tfstate
```

Checkpoint:

- Que archivo aparecio en S3?
- Que pasaria si se borra ese objeto?
- Por que el state debe protegerse?

---

## 17. Limpieza de la app

Primero destruir el recurso de prueba desde `02-app-con-backend`:

```powershell
terraform destroy
```

Confirmar con:

```text
yes
```

Esto borra el bucket de prueba, no el backend.

---

## 18. Limpieza del backend

Volver a bootstrap:

```powershell
cd ../01-backend-bootstrap
```

Antes de destruir backend, verificar que no queden recursos de prueba que dependan de ese state.

Guardar el nombre del bucket antes del primer intento de destruccion:

```powershell
$STATE_BUCKET = terraform output -raw state_bucket_name
```

Ejecutar:

```powershell
terraform destroy
```

Confirmar con:

```text
yes
```

Como el bucket tiene versionado, el primer `terraform destroy` puede borrar la tabla y la configuracion del bucket, pero fallar al eliminar el bucket con `BucketNotEmpty`. En ese caso, eliminar todas las versiones y delete markers antes de reintentar.

Listar las versiones existentes:

```powershell
aws s3api list-object-versions --bucket $STATE_BUCKET
```

Eliminar versiones del state:

```powershell
$VERSIONS = aws s3api list-object-versions `
  --bucket $STATE_BUCKET `
  --query 'Versions[].{Key:Key,VersionId:VersionId}' `
  --output json | ConvertFrom-Json

if ($VERSIONS.Count -gt 0) {
  $DELETE_VERSIONS = @{
    Objects = @($VERSIONS)
    Quiet   = $true
  } | ConvertTo-Json -Depth 5 -Compress

  aws s3api delete-objects `
    --bucket $STATE_BUCKET `
    --delete $DELETE_VERSIONS
}
```

Eliminar delete markers si existen:

```powershell
$DELETE_MARKERS = aws s3api list-object-versions `
  --bucket $STATE_BUCKET `
  --query 'DeleteMarkers[].{Key:Key,VersionId:VersionId}' `
  --output json | ConvertFrom-Json

if ($DELETE_MARKERS.Count -gt 0) {
  $DELETE_MARKER_REQUEST = @{
    Objects = @($DELETE_MARKERS)
    Quiet   = $true
  } | ConvertTo-Json -Depth 5 -Compress

  aws s3api delete-objects `
    --bucket $STATE_BUCKET `
    --delete $DELETE_MARKER_REQUEST
}
```

Reintentar la destruccion:

```powershell
terraform destroy
```

Confirmar con `yes` y validar que el bucket ya no exista:

```powershell
aws s3api head-bucket --bucket $STATE_BUCKET
```

La limpieza fue correcta si AWS responde que el bucket no existe.

---

## 19. Troubleshooting

| Problema | Causa probable | Accion sugerida |
|---|---|---|
| `NoSuchBucket` al inicializar backend | El bucket de state no existe o el nombre esta mal | Revisar outputs del bootstrap y `backend.tf` |
| Error de lock | Hay otra ejecucion usando el mismo state o quedo un lock anterior | Verificar tabla DynamoDB y no forzar unlock sin entender el caso |
| Backend no acepta variables | Terraform no permite variables normales en backend | Escribir valores directos en `backend.tf` para este lab |
| Bucket de state no se borra | Tiene objetos o versiones | Vaciar el bucket y sus versiones antes de destruir |
| AccessDenied | Permisos insuficientes | Validar cuenta y permisos con el docente |

---

## 20. Entregables

Entregar:

1. Nombre del bucket de state.
2. Nombre de la tabla DynamoDB de locks.
3. Contenido de `backend.tf` sin credenciales.
4. Salida de `terraform init` mostrando backend S3 inicializado.
5. Evidencia de state guardado en S3.
6. Explicacion breve: que problema resuelve el backend remoto.
7. Confirmacion de limpieza de app y backend.

---
