# Guia LAB02: Variables con tfvars, outputs y Lambda con Terraform

**Modulo:** M3 - Clase 1: Infrastructure as Code  
**Duracion estimada:** 90 a 120 minutos  
**Proyecto Terraform:** creado por el alumno durante el laboratorio  
**Nivel:** introductorio  

---

## 1. Contexto

En el LAB01 creaste un bucket S3 con un proyecto Terraform minimo: `versions.tf`, `providers.tf` y `main.tf`.

En este laboratorio vas a crear un nuevo proyecto Terraform desde cero. Se suma una funcion Lambda y aparece el primer mecanismo para separar valores del codigo: `terraform.tfvars`.

Para mantener el lab simple, todos los valores variables se van a cargar desde un archivo:

```text
terraform.tfvars
```

La infraestructura creada sera una Lambda simple que responde:

```text
hola desde lambda
```

Luego vas a invocarla desde la terminal con AWS CLI.

---

## 2. Objetivos de aprendizaje

Al finalizar el LAB02 vas a poder:

1. Crear la estructura de un proyecto Terraform desde cero.
2. Declarar variables en `variables.tf`.
3. Asignar valores con `terraform.tfvars`.
4. Usar variables dentro de recursos Terraform.
5. Crear una funcion Lambda simple con Terraform.
6. Crear outputs para recuperar datos utiles del despliegue.
7. Invocar una Lambda usando un output de Terraform.
8. Limpiar los recursos creados con `terraform destroy`.

---

## 3. Arquitectura objetivo

```text
Alumno / Terminal
      |
      | terraform init / plan / apply
      v
Terraform CLI
      |
      | Lee variables.tf + terraform.tfvars
      |
      | Provider AWS
      v
AWS Lambda
      |
      | aws lambda invoke
      v
Respuesta: hola desde lambda
```

Recursos que se van a crear:

- Una funcion Lambda en Python.
- Un rol IAM para que Lambda pueda ejecutarse.
- Una policy administrada de AWS para logs basicos en CloudWatch.

---

## 4. Alcance del LAB02

### Incluido

- Proyecto Terraform creado desde cero.
- Variables en `variables.tf`.
- Valores en `terraform.tfvars`.
- Provider AWS parametrizado por variable.
- Empaquetado local de codigo Lambda con provider `archive`.
- Lambda basica en Python.
- Outputs.
- Invocacion con AWS CLI.
- Limpieza con Terraform.

### No incluido todavia

- Otras formas de cargar variables.
- Modulos.
- Backend remoto S3/DynamoDB.
- API Gateway.
- Pipelines CI/CD.

---

## 5. Pre-requisitos

Antes de empezar, validar que las herramientas esten disponibles:

```powershell
git --version
aws --version
terraform version
```

Validar identidad AWS:

```powershell
aws sts get-caller-identity
```

Si usas el perfil `curso`, configurar la terminal actual para que AWS CLI y Terraform usen ese perfil:

```powershell
$env:AWS_PROFILE="curso"
aws sts get-caller-identity
```

Necesitas permisos para crear y borrar:

- Lambda function.
- IAM role.
- IAM role policy attachment.
- CloudWatch Logs generados por Lambda.

---

## 6. Crear carpeta del laboratorio

Desde la raiz del repositorio:

```powershell
mkdir terraform/iac-lab02-lambda
cd terraform/iac-lab02-lambda
```

Crear carpetas internas:

```powershell
mkdir function
mkdir build
```

Estructura final esperada:

```text
terraform/iac-lab02-lambda/
  versions.tf
  providers.tf
  variables.tf
  terraform.tfvars
  main.tf
  outputs.tf
  .gitignore
  function/
    lambda_function.py
  build/
```

Los archivos los vas a crear en los siguientes pasos.

---

## 7. Crear `.gitignore`

Crear el archivo:

```powershell
New-Item .gitignore
```

Contenido:

```gitignore
.terraform/
*.tfstate
*.tfstate.*
build/
response.json
terraform.tfvars
```

`terraform.tfvars` puede contener valores propios del alumno o del entorno. En este laboratorio no contiene credenciales, pero igual conviene no subirlo al repositorio.

---

## 8. Crear `versions.tf`

Crear el archivo:

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

    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
    }
  }
}
```

En este laboratorio Terraform usa dos providers:

- `aws`: para crear recursos en AWS.
- `archive`: para generar el archivo `.zip` que necesita Lambda.

---

## 9. Crear `providers.tf`

Crear el archivo:

```powershell
New-Item providers.tf
```

Contenido:

```hcl
provider "aws" {
  region = var.aws_region
}
```

La region ya no queda escrita directamente en el provider. Terraform la toma desde la variable `aws_region`, cuyo valor se carga desde `terraform.tfvars`.

---

## 10. Crear `variables.tf`

Crear el archivo:

```powershell
New-Item variables.tf
```

Contenido:

```hcl
variable "aws_region" {
  description = "Region de AWS donde se crean los recursos."
  type        = string
}

variable "lambda_name" {
  description = "Nombre de la funcion Lambda."
  type        = string
}

variable "student_identity" {
  description = "Identidad del alumno o grupo para nomenclatura."
  type        = string
}
```

`variables.tf` declara que valores necesita el proyecto. Todavia no define los valores concretos.

Checkpoint:

- Que diferencia hay entre declarar una variable y asignarle un valor?
- Por que conviene separar nombres, region e iniciales del codigo principal?

---

## 11. Crear `terraform.tfvars`

Crear el archivo:

```powershell
New-Item terraform.tfvars
```

Contenido ejemplo:

```hcl
aws_region       = "us-east-1"
student_identity = "tu-identidad"
lambda_name      = "lambda-hola-tu-identidad"
```

Cada alumno debe cambiar:

- `student_identity`: por su identidad o identificador del grupo.
- `lambda_name`: por un nombre unico para su funcion.

Ejemplo para un grupo con iniciales `ab`:

```hcl
aws_region       = "us-east-1"
student_identity = "ab"
lambda_name      = "lambda-hola-ab"
```

Terraform lee automaticamente el archivo `terraform.tfvars` cuando ejecutas `plan`, `apply` o `destroy`.

Checkpoint:

- Que archivo define las variables?
- Que archivo asigna los valores?
- Que pasaria si falta `lambda_name` en `terraform.tfvars`?

---

## 12. Crear el codigo de Lambda

Crear el archivo:

```powershell
New-Item function/lambda_function.py
```

Contenido:

```python
def lambda_handler(event, context):
    return {
        "statusCode": 200,
        "body": "hola desde lambda"
    }
```

Esta funcion recibe un evento y devuelve un objeto JSON con un mensaje simple.

---

## 13. Crear `main.tf`

Crear el archivo:

```powershell
New-Item main.tf
```

Contenido:

```hcl
data "archive_file" "lambda_zip" {
  type        = "zip"
  source_file = "${path.module}/function/lambda_function.py"
  output_path = "${path.module}/build/lambda_function.zip"
}

resource "aws_iam_role" "lambda_role" {
  name = "${var.lambda_name}-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_basic_logs" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_lambda_function" "hola" {
  function_name = var.lambda_name
  role          = aws_iam_role.lambda_role.arn

  runtime = "python3.12"
  handler = "lambda_function.lambda_handler"

  filename         = data.archive_file.lambda_zip.output_path
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  timeout = 5

  environment {
    variables = {
      STUDENT_INITIALS = var.student_identity
    }
  }
}
```

Puntos importantes:

- `data "archive_file"` crea un `.zip` local con el codigo Python.
- `aws_iam_role` permite que Lambda asuma un rol de ejecucion.
- `AWSLambdaBasicExecutionRole` permite escribir logs basicos en CloudWatch.
- `aws_lambda_function` crea la funcion Lambda.
- `function_name` usa el valor de `var.lambda_name`.
- `source_code_hash` ayuda a Terraform a detectar cambios en el codigo.

---

## 14. Crear `outputs.tf`

Crear el archivo:

```powershell
New-Item outputs.tf
```

Contenido:

```hcl
output "lambda_function_name" {
  description = "Nombre de la funcion Lambda creada."
  value       = aws_lambda_function.hola.function_name
}

output "lambda_function_arn" {
  description = "ARN de la funcion Lambda creada."
  value       = aws_lambda_function.hola.arn
}

output "invoke_command" {
  description = "Comando AWS CLI para invocar la funcion Lambda."
  value       = "aws lambda invoke --function-name ${aws_lambda_function.hola.function_name} --payload '{}' --cli-binary-format raw-in-base64-out response.json"
}
```

Los outputs muestran datos utiles despues del `apply`.

En este caso vas a usar el output `lambda_function_name` para invocar la Lambda desde la terminal.

---

## 15. Inicializar Terraform

Ejecutar:

```powershell
terraform init -backend=false
```

Terraform descarga los providers `aws` y `archive`.

Validar formato y configuracion:

```powershell
terraform fmt
terraform validate
```

Resultado esperado:

```text
Success! The configuration is valid.
```

---

## 16. Revisar el plan

Ejecutar:

```powershell
terraform plan
```

Terraform lee automaticamente los valores desde `terraform.tfvars`.

El plan debe mostrar creacion de recursos similares a:

```text
aws_iam_role.lambda_role
aws_iam_role_policy_attachment.lambda_basic_logs
aws_lambda_function.hola
```

Revisar especialmente:

- nombre de la Lambda;
- region activa;
- rol IAM a crear;
- archivo `.zip` que se va a usar;
- outputs que van a quedar disponibles.

Checkpoint:

- Que recursos se van a crear?
- Que valores salieron de `terraform.tfvars`?
- Que diferencia hay entre revisar un plan y crear recursos directamente desde consola?

---

## 17. Crear la Lambda

Ejecutar solo si tenes autorizacion para crear recursos en la cuenta AWS:

```powershell
terraform apply
```

Confirmar:

```text
yes
```

Al finalizar, Terraform debe mostrar los outputs.

Tambien podes consultarlos manualmente:

```powershell
terraform output
```

Obtener solo el nombre de la Lambda:

```powershell
terraform output -raw lambda_function_name
```

---

## 18. Invocar la Lambda desde la terminal

Guardar el nombre de la funcion en una variable de PowerShell:

```powershell
$FUNCTION_NAME = terraform output -raw lambda_function_name
```

Invocar la Lambda:

```powershell
aws lambda invoke `
  --function-name $FUNCTION_NAME `
  --payload '{}' `
  --cli-binary-format raw-in-base64-out `
  response.json
```

Ver la respuesta:

```powershell
Get-Content response.json
```

Resultado esperado:

```json
{"statusCode":200,"body":"hola desde lambda"}
```

Tambien podes ver el comando sugerido por Terraform:

```powershell
terraform output -raw invoke_command
```

Ese output no ejecuta el comando automaticamente. Solo muestra el comando construido con el nombre real de la Lambda.

---

## 19. Probar un cambio de codigo

Editar `function/lambda_function.py` y cambiar el mensaje:

```python
def lambda_handler(event, context):
    return {
        "statusCode": 200,
        "body": "hola desde lambda actualizado"
    }
```

Aplicar formato y revisar plan:

```powershell
terraform fmt
terraform plan
```

Terraform debe detectar un cambio en el paquete de Lambda por el `source_code_hash`.

Aplicar el cambio:

```powershell
terraform apply
```

Volver a invocar:

```powershell
aws lambda invoke `
  --function-name $FUNCTION_NAME `
  --payload '{}' `
  --cli-binary-format raw-in-base64-out `
  response.json

Get-Content response.json
```

---

## 20. Revisar estado local

Despues del `apply`, Terraform crea o actualiza:

```text
terraform.tfstate
```

Ese archivo contiene el estado local de los recursos administrados.

En este laboratorio, el estado queda en tu maquina. Mas adelante vas a usar backend remoto para guardar el estado en S3 y manejar bloqueo con DynamoDB.

Checkpoint:

- Que diferencia hay entre el archivo `terraform.tfvars` y `terraform.tfstate`?
- Cual escribiste vos?
- Cual mantiene Terraform?
- Cual no deberias compartir si contiene datos del entorno?

---

## 21. Limpieza

Antes de destruir, guardar el nombre de la funcion si no lo tenes en la terminal:

```powershell
$FUNCTION_NAME = terraform output -raw lambda_function_name
```

Borrar los recursos creados por Terraform:

```powershell
terraform destroy
```

Confirmar:

```text
yes
```

Validar que la funcion ya no exista:

```powershell
aws lambda get-function --function-name $FUNCTION_NAME
```

Si AWS responde que la funcion no existe, la limpieza fue correcta.

Si invocaste la Lambda, AWS pudo haber creado un log group en CloudWatch Logs. Borrarlo para no dejar recursos residuales:

```powershell
aws logs delete-log-group --log-group-name "/aws/lambda/$FUNCTION_NAME"
```

Si el log group no existe, AWS va a devolver un error de no encontrado. En ese caso no hay nada mas para borrar.

---

## 22. Troubleshooting

| Problema | Causa probable | Accion sugerida |
|---|---|---|
| Terraform pide un valor interactivo | Falta una variable en `terraform.tfvars` | Revisar `aws_region`, `student_identity` y `lambda_name` |
| Terraform no toma un cambio de variable | El archivo no se llama exactamente `terraform.tfvars` o esta en otra carpeta | Verificar nombre y ubicacion del archivo |
| `Archive creation error` | No existe `function/lambda_function.py` o `build/` | Revisar estructura de carpetas |
| `AccessDenied` al crear IAM | El usuario no tiene permisos IAM | Validar permisos de la cuenta de laboratorio |
| `ResourceConflictException` | Ya existe una Lambda con ese nombre | Cambiar `lambda_name` en `terraform.tfvars` |
| `InvalidParameterValueException` | Handler, runtime o ZIP incorrecto | Revisar `handler`, `runtime` y archivo Python |
| Invoke no muestra el body esperado | Se invoco otra funcion o no se aplico el cambio | Revisar `$FUNCTION_NAME`, `terraform output` y volver a ejecutar `terraform apply` |

---

## 23. Entregables

Entregar:

1. Captura o salida del `terraform plan` donde se vean los recursos a crear.
2. Contenido de `variables.tf`.
3. Contenido de `terraform.tfvars`, sin credenciales ni datos sensibles.
4. Salida de `terraform output` luego del `apply`.
5. Respuesta de la Lambda con `hola desde lambda`.
6. Confirmacion de limpieza con `terraform destroy`.

---
