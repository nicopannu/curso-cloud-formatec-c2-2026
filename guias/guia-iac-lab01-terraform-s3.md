# Guia LAB01: Terraform minimo con un bucket S3

**Modulo:** M3 - Clase 1: Infrastructure as Code  
**Duracion estimada:** 90 a 120 minutos  
**Proyecto Terraform:** `terraform/iac-lab01-s3-basics/`  
**Nivel:** introductorio  

---

## 1. Contexto narrativo

Hasta ahora muchas decisiones de infraestructura se pueden ejecutar desde consola: crear recursos, elegir regiones, configurar nombres y validar que algo exista.

El problema aparece cuando queremos responder preguntas simples:

- Que se creo exactamente?
- Quien lo cambio?
- Como repetimos el mismo entorno?
- Como revisamos un cambio antes de aplicarlo?
- Como limpiamos recursos sin olvidarnos nada?

Terraform permite tratar infraestructura como codigo. En este primer laboratorio vas a trabajar con una estructura minima de proyecto y con el ciclo de trabajo basico.

El recurso elegido es un bucket S3 porque es simple, barato, facil de identificar y facil de borrar.

---

## 2. Objetivos de aprendizaje

Al finalizar el LAB01, el alumno deberia poder:

1. Reconocer los archivos minimos de un proyecto Terraform.
2. Explicar la diferencia entre Terraform, provider y recurso.
3. Ejecutar `terraform init`, `fmt`, `validate` y `plan`.
4. Interpretar que significa que Terraform proponga crear un recurso.
5. Entender que `apply` y `destroy` modifican recursos reales.
6. Identificar el archivo de estado local como registro de lo que Terraform administra.

En este laboratorio vas a trabajar sin variables, outputs, locals, modulos ni backend remoto. Esos conceptos aparecen en los siguientes laboratorios.

---

## 3. Alcance del LAB01

### Incluido

- Preparacion de terminal con Git, AWS CLI y Terraform.
- Clonado del repositorio del curso.
- Revision de un proyecto Terraform minimo.
- Creacion planificada de un bucket S3.
- Discusion sobre plan, apply, state y destroy.

### No incluido todavia

- Variables (`variables.tf`, `terraform.tfvars`, `-var`, `TF_VAR_*`).
- Outputs.
- Locals.
- Lambda.
- Modulos.
- Backend remoto S3/DynamoDB.
- Pipelines CI/CD.

---

## 4. Progresion prevista

La secuencia propuesta para el modulo IaC queda asi:

1. **LAB01:** proyecto Terraform minimo y primer recurso S3.
2. **LAB02:** variables para parametrizar region, cuenta, iniciales, nombres y tags.
3. **LAB03:** Lambda reutilizando variables ya definidas.
4. **LAB04:** modulos para separar responsabilidades y reutilizar infraestructura.
5. **LAB05:** backend remoto con S3 y DynamoDB para estado compartido y bloqueo.

Esta guia cubre solo el LAB01.

---

## 5. Arquitectura objetivo del LAB01

Arquitectura minima:

```text
Alumno / Terminal
      |
      | terraform init / validate / plan / apply
      v
Terraform CLI
      |
      | Provider AWS
      v
AWS S3 Bucket
```

No hay aplicacion, no hay Lambda, no hay red propia, no hay ALB, no hay base de datos.

La pregunta central es:

> Como pasa Terraform de un archivo `.tf` a un plan de infraestructura en AWS?

---

## 6. Pre-requisitos

Cada alumno necesita:

- Windows con PowerShell.
- Visual Studio Code u otro IDE equivalente.
- Git instalado.
- AWS CLI instalado.
- Terraform instalado.
- Credenciales AWS autorizadas para realizar el laboratorio.
- Permisos para crear y borrar un bucket S3 en la cuenta de laboratorio.

Validaciones iniciales:

```powershell
git --version
aws --version
terraform version
```

Si algun comando no existe, instalarlo antes de seguir.

---

## 7. Preparacion de herramientas en Windows

### Opcion recomendada: winget

```powershell
winget --version
```

Si `winget` esta disponible:

```powershell
winget install --id Git.Git -e
winget install --id Amazon.AWSCLI -e
winget install --id Hashicorp.Terraform -e
```

Cerrar y volver a abrir PowerShell.

Validar:

```powershell
git --version
aws --version
terraform version
```

### Opcion alternativa: Chocolatey

Si el alumno ya usa Chocolatey:

```powershell
choco install git awscli terraform -y
```

Cerrar y volver a abrir PowerShell.

---

## 8. Configurar acceso AWS

Si recibiste credenciales para un perfil llamado `curso`:

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

Esperado: AWS devuelve un `Account`, un `UserId` y un `Arn`.

Para que Terraform use ese perfil en la terminal actual:

```powershell
$env:AWS_PROFILE="curso"
```

Validar nuevamente:

```powershell
aws sts get-caller-identity
```

Checkpoint oral:

- Que cuenta AWS estoy usando?
- Que perfil de AWS CLI quedo activo?
- Por que conviene validar identidad antes de crear recursos?

---

## 9. Obtener el material

Clonar el repositorio:

```powershell
git clone https://github.com/nicopannu/curso-cloud-formatec-c2-2026.git
cd curso-cloud-formatec-c2-2026
git checkout m3-c1-lab
```

Entrar al proyecto Terraform del LAB01:

```powershell
cd terraform/iac-lab01-s3-basics
```

Abrir la carpeta en el IDE para ver los archivos.

---

## 10. Estructura minima del proyecto

El proyecto contiene solamente estos archivos Terraform:

```text
terraform/iac-lab01-s3-basics/
  versions.tf
  providers.tf
  main.tf
  README.md
```

### `versions.tf`

Define versiones requeridas:

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

Explicacion:

- `terraform`: bloque de configuracion general.
- `required_version`: version minima de Terraform CLI.
- `required_providers`: plugins que Terraform necesita.
- `hashicorp/aws`: provider oficial para interactuar con AWS.

### `providers.tf`

Configura el provider:

```hcl
provider "aws" {
  region = "us-east-1"
}
```

Explicacion:

- Terraform no habla con AWS por si solo.
- Usa un provider.
- El provider necesita una region.
- Las credenciales no se escriben en el `.tf`; se toman del ambiente/AWS CLI.

### `main.tf`

Declara el recurso:

```hcl
resource "aws_s3_bucket" "lab" {
  bucket = "s3-bucket-485617552563-np"
}
```

Explicacion:

- `resource`: declara infraestructura administrada por Terraform.
- `aws_s3_bucket`: tipo de recurso del provider AWS.
- `lab`: nombre local dentro de Terraform.
- `bucket`: nombre real del bucket en AWS.

Importante: en LAB01 el nombre esta escrito directamente. Esto es intencional para no introducir variables todavia.

---

## 11. Ajustar el nombre del bucket

Antes de planificar, cada alumno debe cambiar el nombre del bucket en `main.tf`.

Patron recomendado:

```text
s3-bucket-NUMERO_DE_CUENTA-INICIALES
```

Ejemplo:

```text
s3-bucket-485617552563-np
```

Reglas practicas para nombres S3:

- Debe ser globalmente unico.
- Usar minusculas, numeros y guiones.
- No usar espacios.
- No usar guion bajo.
- Evitar datos sensibles o nombres personales completos.

Checkpoint oral:

- Por que S3 exige nombres globales?
- Que problema aparece si dos alumnos usan exactamente el mismo nombre?
- Que parte de este nombre hace que sea mas dificil colisionar?

---

## 12. Inicializar Terraform

Ejecutar:

```powershell
terraform init -backend=false
```

Que ocurre:

- Terraform lee los archivos `.tf`.
- Detecta que necesita el provider AWS.
- Descarga el plugin del provider.
- Crea archivos/directorios locales de trabajo.

Usamos `-backend=false` porque el LAB01 todavia no enseña backend remoto. El estado sera local.

Checkpoint:

- Que provider descargo Terraform?
- Que archivo lock aparece luego del init?
- Por que todavia no se creo ningun recurso AWS?

---

## 13. Formatear y validar

Formatear:

```powershell
terraform fmt
```

Validar sintaxis y estructura:

```powershell
terraform validate
```

Resultado esperado:

```text
Success! The configuration is valid.
```

Diferencia conceptual:

- `fmt` ordena formato.
- `validate` revisa que la configuracion sea valida para Terraform.
- Ninguno de los dos crea recursos.

---

## 14. Ver el plan

Ejecutar:

```powershell
terraform plan
```

Terraform deberia mostrar que quiere crear un bucket S3.

Buscar en la salida:

```text
# aws_s3_bucket.lab will be created
+ resource "aws_s3_bucket" "lab" {
    + bucket = "s3-bucket-..."
}
```

Explicacion:

- `+` significa crear.
- `-` significaria destruir.
- `~` significaria modificar.
- El plan permite revisar antes de tocar AWS.

Checkpoint oral:

- Que recurso se crearia?
- En que region se crearia?
- Que nombre real tendria en AWS?
- Por que conviene revisar el plan antes del apply?

---

## 15. Apply con autorizacion

No ejecutes este paso si no tenes autorizacion para crear recursos reales.

Si esta autorizado:

```powershell
terraform apply
```

Terraform pedira confirmacion:

```text
Do you want to perform these actions?
```

Responder:

```text
yes
```

Luego validar en AWS CLI:

```powershell
aws s3 ls
```

O buscar el bucket especifico:

```powershell
aws s3api head-bucket --bucket s3-bucket-485617552563-np
```

Reemplazar el nombre por el que haya usado el alumno.

Checkpoint:

- Que cambio entre `plan` y `apply`?
- Donde queda registrado lo creado?
- Si borro el bucket desde consola, Terraform se entera automaticamente?

---

## 16. Estado local

Despues de aplicar, Terraform crea o actualiza:

```text
terraform.tfstate
```

Este archivo representa lo que Terraform cree administrar.

Puntos clave:

- No es documentacion humana.
- Es informacion operativa de Terraform.
- Puede contener datos sensibles en escenarios reales.
- No deberia subirse al repositorio.
- En equipos de trabajo, se reemplaza por backend remoto.

El backend remoto se trabaja mas adelante con S3 + DynamoDB para estado compartido y locking.

---

## 17. Destroy y limpieza

Al finalizar el laboratorio, si se creo el bucket:

```powershell
terraform destroy
```

Confirmar con:

```text
yes
```

Validar que ya no exista:

```powershell
aws s3api head-bucket --bucket s3-bucket-485617552563-np
```

Si devuelve error de no encontrado o acceso no valido para ese bucket, revisa el nombre usado y la cuenta activa. El objetivo es no dejar recursos creados innecesariamente.

---

## 18. Troubleshooting

| Problema | Causa probable | Accion sugerida |
|---|---|---|
| `terraform: command not found` | Terraform no esta instalado o la terminal no recargo PATH | Reabrir PowerShell o reinstalar Terraform |
| `No valid credential sources found` | Terraform no encuentra credenciales AWS | Revisar `$env:AWS_PROFILE` y `aws sts get-caller-identity` |
| `BucketAlreadyExists` | El nombre del bucket ya existe globalmente | Cambiar iniciales o agregar un sufijo corto |
| `AccessDenied` | El usuario no tiene permisos suficientes | Validar que el perfil y la cuenta AWS sean los correctos |
| `Error acquiring the state lock` | No deberia ocurrir con estado local simple | Revisar si otro proceso Terraform esta corriendo |

---

## 19. Actividad en clase

Trabajo individual o en grupos pequenos:

1. Abrir los tres archivos Terraform.
2. Identificar que hace cada archivo.
3. Cambiar el nombre del bucket.
4. Ejecutar `init`, `fmt`, `validate` y `plan`.
5. Explicar oralmente que propone el plan.
6. Si tenes autorizacion para crear recursos, ejecutar `apply`.
7. Observar el estado local.
8. Ejecutar `destroy` al terminar.

---

## 20. Entregables / evidencia de clase

Para este LAB01 no se propone una entrega formal extensa. La evidencia minima de trabajo puede ser:

- Captura o copia de salida de `terraform validate` exitoso.
- Captura o copia del fragmento de `terraform plan` donde aparece `aws_s3_bucket.lab`.
- Respuesta breve: que rol cumple `versions.tf`, `providers.tf` y `main.tf`.
- Si hubo apply autorizado: evidencia de creacion y posterior destroy del bucket.

---

## 21. Criterios de evaluacion

| Criterio | Esperado |
|---|---|
| Comprension de estructura | Distingue version/provider/recurso sin mezclar variables o modulos todavia |
| Uso de CLI | Ejecuta init, fmt, validate y plan en orden correcto |
| Lectura del plan | Puede explicar que se va a crear antes del apply |
| Seguridad operativa | No ejecuta apply/destroy sin autorizacion para usar AWS |
| Limpieza | Si crea recursos, tambien ejecuta destroy al final |

---

## 22. Cierre conceptual

Preguntas para cerrar la clase:

1. Que gano al declarar infraestructura en archivos en vez de crearla manualmente?
2. Que parte del proyecto le dice a Terraform como hablar con AWS?
3. Que parte representa la infraestructura deseada?
4. Que diferencia hay entre `validate` y `plan`?
5. Por que el estado local no alcanza para un equipo de trabajo?
6. Que problema empieza a aparecer por tener el nombre del bucket hardcodeado?

Esa pregunta conecta este laboratorio con el siguiente: variables.
