# Formatec Cloud 2026 — M3-C1 IaC Lab

Repositorio del curso Arquitectura e Ingenieria Cloud | C2

Profesor: Nicolas Pannucio

## Branch actual

Esta branch contiene el material de:

| Branch | Modulo | Contenido |
|---|---|---|
| `m3-c1-lab` | M3 - Clase 1 | Introduccion progresiva a Infrastructure as Code con Terraform sobre AWS |

## Laboratorios incluidos

| LAB | Guia | Proyecto Terraform | Foco |
|---|---|---|---|
| LAB01 | `guias/guia-iac-lab01-terraform-s3.md` | `terraform/iac-lab01-s3-basics/` | Primer recurso con Terraform: bucket S3 simple, nombres claros, init, fmt, validate, plan, apply, state y destroy |
| LAB02 | `guias/guia-iac-lab02-terraform-lambda.md` | Creado por el alumno durante la guia | Se suma Lambda e inicia el uso de variables con `terraform.tfvars`, outputs e invoke desde AWS CLI |

## Progresion prevista del modulo IaC

El modulo esta organizado por etapas para incorporar los conceptos de Terraform de forma progresiva:

1. LAB01: primer proyecto Terraform y bucket S3 simple, con valores escritos directamente en los archivos.
2. LAB02: se suma Lambda y se introducen variables desde `terraform.tfvars`, outputs e invocacion con AWS CLI.
3. LAB03: reutilizacion de variables y ampliacion de la funcion Lambda.
4. LAB04: modulos para ordenar y reutilizar infraestructura.
5. LAB05: backend remoto con S3 y DynamoDB para estado compartido y locking.

## Escenario de trabajo

El laboratorio esta pensado para trabajar con:

- Windows como sistema operativo del alumno.
- Un IDE con terminal integrada, por ejemplo Visual Studio Code ya instalado por el alumno.
- Git para clonar el repositorio.
- AWS CLI para validar credenciales y cuenta.
- Terraform para declarar y crear infraestructura.
- Cuenta AWS de laboratorio o sandbox autorizada para realizar el lab.

No se incluyen pasos de instalacion del IDE. El foco de preparacion es dejar lista la terminal para usar Git, AWS CLI y Terraform.

## Preparacion en Windows

Abrir PowerShell como usuario normal. Si una instalacion falla por permisos, abrir PowerShell como Administrador.

### Opcion recomendada: winget

Verificar si `winget` esta disponible:

```powershell
winget --version
```

Instalar Git, AWS CLI y Terraform:

```powershell
winget install --id Git.Git -e
winget install --id Amazon.AWSCLI -e
winget install --id Hashicorp.Terraform -e
```

Cerrar y volver a abrir la terminal. Luego validar:

```powershell
git --version
aws --version
terraform version
```

### Opcion alternativa: Chocolatey

Chocolatey tambien sirve, especialmente si el alumno ya lo tiene instalado. Si no esta instalado, `winget` suele ser mas directo en Windows moderno.

Con Chocolatey disponible:

```powershell
choco install git awscli terraform -y
```

Cerrar y volver a abrir la terminal. Luego validar:

```powershell
git --version
aws --version
terraform version
```

## Configurar credenciales AWS

Si recibiste credenciales para un perfil de laboratorio:

```powershell
aws configure --profile curso
```

Completar:

- AWS Access Key ID
- AWS Secret Access Key
- Default region name: `us-east-1`
- Default output format: `json`

Validar identidad sin crear recursos:

```powershell
aws sts get-caller-identity --profile curso
```

Para usar ese perfil con Terraform en la terminal actual:

```powershell
$env:AWS_PROFILE="curso"
```

Verificar:

```powershell
aws sts get-caller-identity
```

## Como usar esta branch

Clonar el repositorio y cambiar a la branch del laboratorio:

```powershell
git clone https://github.com/nicopannu/curso-cloud-formatec-c2-2026.git
cd curso-cloud-formatec-c2-2026
git checkout m3-c1-lab
```

Abrir la carpeta en el IDE y seguir la guia correspondiente:

- LAB01: `guias/guia-iac-lab01-terraform-s3.md`
- LAB02: `guias/guia-iac-lab02-terraform-lambda.md`

Para LAB01, entrar al proyecto ya incluido:

```powershell
cd terraform/iac-lab01-s3-basics
```

Antes de planificar, editar `main.tf` y cambiar el nombre del bucket por uno propio siguiendo el patron:

```text
s3-bucket-NUMERO_DE_CUENTA-INICIALES
```

Flujo inicial:

```powershell
terraform init -backend=false
terraform fmt
terraform validate
terraform plan
```

`terraform apply` y `terraform destroy` modifican recursos reales en AWS. Ejecutalos solo cuando tengas autorizacion para usar la cuenta de laboratorio.

## Idea central de la clase

Si la infraestructura se crea a mano, no es repetible. Si no es repetible, no es confiable.

El LAB01 muestra el flujo minimo de Terraform con un bucket S3. El LAB02 agrega Lambda y empieza a separar los valores variables en `terraform.tfvars` para que el proyecto sea mas claro y reutilizable.

---

Proyecto educativo — Formatec Cloud Course 2026
