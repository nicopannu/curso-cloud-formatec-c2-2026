# Guia LAB04: Data sources, locals y nomenclatura

**Modulo:** M3 - Clase 1: Infrastructure as Code  
**Duracion estimada:** 90 a 120 minutos  
**Proyecto Terraform:** creado por el alumno durante el laboratorio  
**Nivel:** intermedio inicial  

---

## 1. Contexto

En los laboratorios anteriores usaste valores escritos directamente y variables cargadas desde `terraform.tfvars`.

En este laboratorio vas a mejorar la forma de construir nombres y tags. Terraform no solo puede crear recursos: tambien puede leer datos del contexto AWS, como la cuenta y la region actual.

La pregunta central es:

> Que valores deberia recibir el proyecto y que valores puede calcular automaticamente?

---

## 2. Objetivos de aprendizaje

Al finalizar el LAB04 vas a poder:

1. Diferenciar `resource` y `data`.
2. Leer la cuenta AWS actual con `aws_caller_identity`.
3. Leer la region actual con `aws_region`.
4. Crear valores calculados con `locals`.
5. Aplicar una nomenclatura consistente para recursos.
6. Definir tags comunes para recursos AWS.
7. Usar outputs para revisar nombres, cuenta y region.

---

## 3. Arquitectura objetivo

```text
Terraform CLI
      |
      | data sources
      v
Cuenta AWS / Region actual
      |
      | locals + variables
      v
Nombres y tags consistentes
      |
      v
S3 Bucket de laboratorio
```

Este laboratorio vuelve a usar S3 porque permite enfocarse en data sources, locals y nombres sin agregar complejidad de aplicacion.

---

## 4. Alcance del LAB04

### Incluido

- Variables desde `terraform.tfvars`.
- Data sources de cuenta y region.
- Locals para nombres y tags.
- Bucket S3 con nombre calculado.
- Outputs de verificacion.
- Limpieza del recurso.

### No incluido todavia

- Modulos.
- Backend remoto.
- Import.
- Workspaces.
- Pipelines.

---

## 5. Pre-requisitos

Necesitas haber completado LAB01 y LAB02, o contar con experiencia basica ejecutando:

```powershell
terraform init
terraform validate
terraform plan
terraform apply
terraform destroy
```

Validar herramientas:

```powershell
git --version
aws --version
terraform version
```

Validar identidad AWS:

```powershell
aws sts get-caller-identity
```

Tambien necesitas permisos para crear y borrar buckets S3 en la cuenta de laboratorio.

---

## 6. Crear carpeta del laboratorio

Desde la raiz del repositorio:

```powershell
mkdir terraform/iac-lab04-data-locals
cd terraform/iac-lab04-data-locals
```

Estructura final:

```text
terraform/iac-lab04-data-locals/
  versions.tf
  providers.tf
  variables.tf
  terraform.tfvars
  data.tf
  locals.tf
  main.tf
  outputs.tf
  .gitignore
```

---

## 7. Crear `.gitignore`

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

## 8. Crear `versions.tf`

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

---

## 9. Crear `providers.tf`

```powershell
New-Item providers.tf
```

Contenido:

```hcl
provider "aws" {
  region = var.aws_region
}
```

---

## 10. Crear `variables.tf`

```powershell
New-Item variables.tf
```

Contenido:

```hcl
variable "aws_region" {
  description = "Region AWS para trabajar."
  type        = string
}

variable "project" {
  description = "Nombre corto del proyecto."
  type        = string
}

variable "environment" {
  description = "Ambiente de trabajo."
  type        = string
}

variable "student_identity" {
  description = "Identidad del alumno o grupo para nomenclatura."
  type        = string
}
```

---

## 11. Crear `terraform.tfvars`

```powershell
New-Item terraform.tfvars
```

Contenido ejemplo:

```hcl
aws_region       = "us-east-1"
project          = "formatec"
environment      = "lab"
student_identity = "tu-identidad"
```

Cambiar `student_identity` por tu identidad o identificador del grupo.

---

## 12. Crear `data.tf`

```powershell
New-Item data.tf
```

Contenido:

```hcl
data "aws_caller_identity" "current" {}

data "aws_region" "current" {}
```

Explicacion:

- `data.aws_caller_identity.current` permite leer datos de la cuenta activa.
- `data.aws_region.current` permite leer la region activa del provider.
- Un `data` source lee informacion. No administra el recurso.

Checkpoint:

- Que diferencia hay entre `data` y `resource`?
- Terraform esta creando la cuenta AWS?
- Terraform esta creando la region?

---

## 13. Crear `locals.tf`

```powershell
New-Item locals.tf
```

Contenido:

```hcl
locals {
  name_prefix = "${var.project}-${var.environment}-${var.student_identity}"

  bucket_name = "${local.name_prefix}-${data.aws_caller_identity.current.account_id}"

  common_tags = {
    Project     = var.project
    Environment = var.environment
    Owner       = var.student_identity
    Course      = "formatec"
    ManagedBy   = "terraform"
  }
}
```

Explicacion:

- Una variable entra desde afuera.
- Un local se calcula dentro del proyecto.
- `bucket_name` combina variables y datos leidos desde AWS.
- `common_tags` evita repetir tags en cada recurso.

Checkpoint:

- Que valores vienen de `terraform.tfvars`?
- Que valor viene desde AWS?
- Que valores calcula Terraform?

---

## 14. Crear `main.tf`

```powershell
New-Item main.tf
```

Contenido:

```hcl
resource "aws_s3_bucket" "lab" {
  bucket = local.bucket_name

  tags = local.common_tags
}
```

El bucket ya no tiene un nombre escrito directamente. El nombre se calcula con `local.bucket_name`.

---

## 15. Crear `outputs.tf`

```powershell
New-Item outputs.tf
```

Contenido:

```hcl
output "account_id" {
  description = "ID de la cuenta AWS activa."
  value       = data.aws_caller_identity.current.account_id
}

output "aws_region" {
  description = "Region AWS activa."
  value       = data.aws_region.current.name
}

output "bucket_name" {
  description = "Nombre final del bucket creado."
  value       = aws_s3_bucket.lab.bucket
}

output "common_tags" {
  description = "Tags comunes aplicados al recurso."
  value       = local.common_tags
}
```

---

## 16. Inicializar y validar

```powershell
terraform init -backend=false
terraform fmt
terraform validate
```

Resultado esperado:

```text
Success! The configuration is valid.
```

---

## 17. Revisar el plan

```powershell
terraform plan
```

Revisar:

- nombre final del bucket;
- tags aplicados;
- cuenta AWS usada;
- region usada.

Checkpoint:

- El nombre del bucket incluye la cuenta AWS?
- Los tags salen de un solo lugar?
- Que pasaria si cambias `environment` en `terraform.tfvars`?

---

## 18. Crear el recurso

Ejecutar solo con autorizacion:

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

Validar el bucket:

```powershell
aws s3api head-bucket --bucket $(terraform output -raw bucket_name)
```

En PowerShell, si el comando anterior no funciona por sintaxis, copiar el valor de `bucket_name` y ejecutar:

```powershell
aws s3api head-bucket --bucket NOMBRE_DEL_BUCKET
```

---

## 19. Probar un cambio de nomenclatura

Editar `terraform.tfvars`:

```hcl
environment = "dev"
```

Ejecutar:

```powershell
terraform plan
```

Revisar si Terraform propone crear, reemplazar o destruir recursos.

Importante: cambiar el nombre de un bucket suele implicar reemplazarlo. Leer el plan antes de aplicar.

Checkpoint:

- Que cambio provoco modificar `environment`?
- Por que un cambio de nombre puede forzar reemplazo?
- Conviene aplicar este cambio o solo observar el plan?

---

## 20. Limpieza

Volver `terraform.tfvars` al valor que se aplico, si lo cambiaste solo para observar el plan.

Destruir recursos creados:

```powershell
terraform destroy
```

Confirmar con:

```text
yes
```

---

## 21. Troubleshooting

| Problema | Causa probable | Accion sugerida |
|---|---|---|
| Bucket name invalido | El nombre calculado tiene caracteres no permitidos | Usar minusculas, numeros y guiones en variables |
| BucketAlreadyExists | El nombre ya existe globalmente | Cambiar `student_identity` o `environment` |
| `data.aws_caller_identity` falla | Credenciales AWS no configuradas | Ejecutar `aws sts get-caller-identity` |
| Plan propone reemplazar el bucket | Cambio el nombre final del recurso | Leer plan y no aplicar si no corresponde |

---

## 22. Entregables

Entregar:

1. Contenido de `data.tf`.
2. Contenido de `locals.tf`.
3. Salida de `terraform output`.
4. Nombre final del bucket.
5. Explicacion breve: que valores vienen de variables, que valores vienen de data sources y que valores se calculan en locals.
6. Confirmacion de limpieza.

---
