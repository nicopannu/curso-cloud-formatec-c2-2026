# Guia LAB05: Modulos locales en Terraform

**Modulo:** M3 - Clase 1: Infrastructure as Code  
**Duracion estimada:** 120 minutos  
**Proyecto Terraform:** creado por el alumno durante el laboratorio  
**Nivel:** intermedio  

---

## 1. Contexto

En LAB04 ordenaste nombres y tags usando variables, data sources y locals. Ahora vas a separar una parte de la infraestructura para reutilizarla.

Un modulo permite agrupar recursos y exponer una interfaz clara mediante variables y outputs.

La pregunta central es:

> Como evito copiar y pegar la misma infraestructura en varios lugares?

---

## 2. Objetivos de aprendizaje

Al finalizar el LAB05 vas a poder:

1. Diferenciar root module y child module.
2. Crear un modulo local.
3. Pasar valores al modulo con variables.
4. Exponer datos desde el modulo con outputs.
5. Reutilizar el mismo modulo mas de una vez.
6. Evaluar cuando un modulo simplifica y cuando oculta demasiado.

---

## 3. Arquitectura objetivo

```text
Root module
  |
  | llama 2 veces
  v
modules/s3-basic
  |
  v
S3 Bucket A
S3 Bucket B
```

Este laboratorio usa S3 para enfocarse en modulos. El patron aplica luego a Lambda, redes, permisos y otros recursos.

---

## 4. Alcance del LAB05

### Incluido

- Modulo local `s3-basic`.
- Variables del modulo.
- Outputs del modulo.
- Dos instancias del mismo modulo.
- Tags comunes.
- Plan, apply y destroy.

### No incluido todavia

- Registry de modulos.
- Versionado de modulos remotos.
- Backend remoto.
- Workspaces.
- Pipelines.

---

## 5. Pre-requisitos

Necesitas haber completado LAB01, LAB02 y LAB04, o contar con experiencia basica con:

- variables;
- `terraform.tfvars`;
- locals;
- outputs;
- lectura de `terraform plan`.

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
mkdir terraform/iac-lab05-modulos
cd terraform/iac-lab05-modulos
mkdir modules
mkdir modules/s3-basic
```

Estructura final:

```text
terraform/iac-lab05-modulos/
  versions.tf
  providers.tf
  variables.tf
  terraform.tfvars
  locals.tf
  main.tf
  outputs.tf
  .gitignore
  modules/
    s3-basic/
      main.tf
      variables.tf
      outputs.tf
```

---

## 6. Crear `.gitignore`

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

## 7. Crear archivos base del root module

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

---

## 8. Crear variables del root module

Crear `variables.tf`:

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

variable "student_initials" {
  description = "Iniciales del alumno o grupo."
  type        = string
}
```

Crear `terraform.tfvars`:

```powershell
New-Item terraform.tfvars
```

Contenido ejemplo:

```hcl
aws_region       = "us-east-1"
project          = "formatec"
environment      = "lab"
student_initials = "np"
```

---

## 9. Crear locals del root module

Crear `locals.tf`:

```powershell
New-Item locals.tf
```

Contenido:

```hcl
locals {
  name_prefix = "${var.project}-${var.environment}-${var.student_initials}"

  common_tags = {
    Project     = var.project
    Environment = var.environment
    Owner       = var.student_initials
    Course      = "formatec"
    ManagedBy   = "terraform"
  }
}
```

---

## 10. Crear el modulo `s3-basic`

Crear `modules/s3-basic/variables.tf`:

```powershell
New-Item modules/s3-basic/variables.tf
```

Contenido:

```hcl
variable "bucket_name" {
  description = "Nombre del bucket S3."
  type        = string
}

variable "tags" {
  description = "Tags a aplicar al bucket."
  type        = map(string)
}
```

Crear `modules/s3-basic/main.tf`:

```powershell
New-Item modules/s3-basic/main.tf
```

Contenido:

```hcl
resource "aws_s3_bucket" "this" {
  bucket = var.bucket_name

  tags = var.tags
}
```

Crear `modules/s3-basic/outputs.tf`:

```powershell
New-Item modules/s3-basic/outputs.tf
```

Contenido:

```hcl
output "bucket_name" {
  description = "Nombre del bucket creado."
  value       = aws_s3_bucket.this.bucket
}

output "bucket_arn" {
  description = "ARN del bucket creado."
  value       = aws_s3_bucket.this.arn
}
```

Checkpoint:

- Que recursos contiene el modulo?
- Que necesita recibir desde afuera?
- Que datos devuelve?

---

## 11. Usar el modulo desde `main.tf`

Crear `main.tf` en la raiz del laboratorio:

```powershell
New-Item main.tf
```

Contenido:

```hcl
module "bucket_logs" {
  source = "./modules/s3-basic"

  bucket_name = "${local.name_prefix}-logs"
  tags        = local.common_tags
}

module "bucket_data" {
  source = "./modules/s3-basic"

  bucket_name = "${local.name_prefix}-data"
  tags        = local.common_tags
}
```

El mismo modulo se usa dos veces con nombres distintos.

---

## 12. Crear outputs del root module

Crear `outputs.tf`:

```powershell
New-Item outputs.tf
```

Contenido:

```hcl
output "logs_bucket_name" {
  description = "Nombre del bucket de logs."
  value       = module.bucket_logs.bucket_name
}

output "data_bucket_name" {
  description = "Nombre del bucket de datos."
  value       = module.bucket_data.bucket_name
}

output "bucket_arns" {
  description = "ARNs de los buckets creados."
  value = {
    logs = module.bucket_logs.bucket_arn
    data = module.bucket_data.bucket_arn
  }
}
```

---

## 13. Inicializar y validar

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

## 14. Revisar el plan

```powershell
terraform plan
```

Revisar:

- que se crean dos buckets;
- que ambos usan el mismo modulo;
- que los nombres son distintos;
- que los tags son consistentes.

Checkpoint:

- Cuantas veces se uso el modulo?
- Cuantos buckets se van a crear?
- Donde se define el recurso real?
- Donde se decide el nombre de cada bucket?

---

## 15. Crear recursos

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

---

## 16. Agregar una tercera instancia

Editar `main.tf` y agregar:

```hcl
module "bucket_reports" {
  source = "./modules/s3-basic"

  bucket_name = "${local.name_prefix}-reports"
  tags        = local.common_tags
}
```

Agregar en `outputs.tf`:

```hcl
output "reports_bucket_name" {
  description = "Nombre del bucket de reportes."
  value       = module.bucket_reports.bucket_name
}
```

Ejecutar:

```powershell
terraform fmt
terraform plan
```

Checkpoint:

- Que se agrego al plan?
- Hubo que copiar el recurso S3 completo?
- Que ventaja trae el modulo?

Aplicar solo si corresponde:

```powershell
terraform apply
```

---

## 17. Limpieza

Destruir recursos:

```powershell
terraform destroy
```

Confirmar con:

```text
yes
```

---

## 18. Troubleshooting

| Problema | Causa probable | Accion sugerida |
|---|---|---|
| `Module not installed` | Falta ejecutar `terraform init` despues de crear/modificar modulo | Ejecutar `terraform init` |
| BucketAlreadyExists | Nombre ya usado globalmente | Cambiar `student_initials` o `environment` |
| Output de modulo no existe | El child module no declara ese output | Revisar `modules/s3-basic/outputs.tf` |
| Plan confuso | Hay varias instancias del mismo modulo | Revisar nombres `module.bucket_logs`, `module.bucket_data`, etc. |

---

## 19. Entregables

Entregar:

1. Estructura de carpetas del laboratorio.
2. Contenido de `modules/s3-basic/main.tf`.
3. Contenido de `main.tf` del root module.
4. Salida de `terraform plan`.
5. Salida de `terraform output` si se aplico.
6. Explicacion breve: que recibe y que devuelve el modulo.
7. Confirmacion de limpieza.

---

## 20. Criterios de evaluacion

| Criterio | Esperado |
|---|---|
| Estructura | El alumno separa root module y child module. |
| Inputs | El modulo recibe valores por variables. |
| Outputs | El modulo devuelve datos utiles. |
| Reutilizacion | El mismo modulo se usa mas de una vez. |
| Plan | El alumno interpreta que recursos crea cada instancia. |
| Limpieza | Los buckets se eliminan al finalizar. |

---

## 21. Cierre para discusion

Responder:

1. Que problema resuelve un modulo?
2. Que parte del codigo quedo reusable?
3. Que decisiones siguen estando en el root module?
4. Que riesgo hay si un modulo oculta demasiados detalles?
5. Cuando conviene crear un modulo y cuando conviene mantener codigo directo?
