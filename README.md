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
| LAB03 | `guias/guia-iac-lab03-state-outputs-cambios.md` | Continuacion del proyecto LAB02 | Outputs, state, cambios controlados y lectura de planes |
| LAB04 | `guias/guia-iac-lab04-data-sources-locals-nomenclatura.md` | Creado por el alumno durante la guia | Data sources, locals, nomenclatura y tags comunes |
| LAB05 | `guias/guia-iac-lab05-modulos-locales.md` | Creado por el alumno durante la guia | Modulos locales, inputs, outputs y reutilizacion |
| LAB06 | `guias/guia-iac-lab06-backend-remoto-s3-dynamodb.md` | Creado por el alumno durante la guia | Backend remoto con S3, DynamoDB y locking |

## Repositorio personal de laboratorios

Cada alumno debe crear un repositorio personal para conservar sus entregables de laboratorio del curso.

Nombre recomendado del repositorio:

```text
curso-cloud-formatec-nombreapellido-c2-2026
```

Reemplazar `nombreapellido` por la identidad del alumno, en minusculas y sin espacios.

Ejemplo:

```text
curso-cloud-formatec-juanperez-c2-2026
```

### Crear el repositorio en GitHub

1. Ingresar a GitHub con la cuenta personal.
2. Abrir el menu `+` y elegir `New repository`.
3. En `Repository name`, escribir el nombre del repositorio personal:

```text
curso-cloud-formatec-nombreapellido-c2-2026
```

4. Elegir visibilidad `Public` o `Private`.
   - Si el repositorio es `Public`, el docente puede revisarlo con el link de entrega.
   - Si el repositorio es `Private`, invitar al docente como colaborador usando este mail: `nicolaspannucio@gmail.com`.
5. No agregar credenciales ni archivos sensibles al repositorio.
6. Se puede crear el repositorio vacio. Tambien es valido marcar `Add a README file` si el alumno quiere dejar una descripcion inicial.
7. Presionar `Create repository`.
8. Copiar la URL del repositorio para clonarlo en la computadora de trabajo.

Ejemplo de URL HTTPS:

```text
https://github.com/<usuario>/curso-cloud-formatec-nombreapellido-c2-2026.git
```

### Branch de entregables

Cada entrega debe realizarse en una branch con la misma nomenclatura que la branch del laboratorio del curso.

Para esta clase, la branch del material del curso es:

```text
m3-c1-lab
```

Por lo tanto, en el repositorio personal del alumno la branch de entrega tambien debe llamarse:

```text
m3-c1-lab
```

Esta regla permite revisar los entregables por modulo y clase sin mezclar trabajos de laboratorios distintos.

### Estructura esperada

La branch `m3-c1-lab` debe contener una carpeta por laboratorio:

```text
curso-cloud-formatec-nombreapellido-c2-2026/
├── lab01/
├── lab02/
├── lab03/
├── lab04/
├── lab05/
└── lab06/
```

Cada carpeta `lab0x/` debe contener los archivos Terraform, notas breves y evidencias solicitadas en la guia correspondiente.

No subir credenciales, claves de acceso, archivos `.env`, perfiles de AWS, carpetas `.terraform/`, archivos `terraform.tfstate`, archivos `.tfstate.backup`, backups locales ni paquetes generados como `.zip`.

### Flujo inicial sugerido

Crear el repositorio en GitHub, copiar su URL y luego ejecutar:

```powershell
git clone URL_DEL_REPOSITORIO_PERSONAL
cd curso-cloud-formatec-nombreapellido-c2-2026
git checkout -b m3-c1-lab
mkdir lab01 lab02 lab03 lab04 lab05 lab06
```

Al finalizar cada laboratorio, guardar el trabajo dentro de la carpeta correspondiente y registrar los cambios:

```powershell
git status
git add lab01
git commit -m "Agregar entrega LAB01 M3 C1"
```

Repetir el mismo criterio para `lab02`, `lab03`, `lab04`, `lab05` y `lab06`.

El link de entrega debe apuntar al repositorio personal y a la branch correspondiente, por ejemplo:

```text
https://github.com/<usuario>/curso-cloud-formatec-nombreapellido-c2-2026/tree/m3-c1-lab
```

## Progresion prevista del modulo IaC

El modulo esta organizado por etapas para incorporar los conceptos de Terraform de forma progresiva:

1. LAB01: primer proyecto Terraform y bucket S3 simple, con valores escritos directamente en los archivos.
2. LAB02: se suma Lambda y se introducen variables desde `terraform.tfvars`, outputs e invocacion con AWS CLI.
3. LAB03: se profundiza en outputs, state y cambios controlados sobre infraestructura ya creada.
4. LAB04: se incorporan data sources, locals, nomenclatura y tags comunes.
5. LAB05: se reorganiza infraestructura con modulos locales.
6. LAB06: se migra el estado a backend remoto con S3 y DynamoDB para locking.

## Escenario de trabajo

El laboratorio esta pensado para trabajar con:

- Windows como sistema operativo del alumno.
- Un IDE con terminal integrada, por ejemplo Visual Studio Code o Cursor.
- Terminal WSL o PowerShell, segun indique el docente.
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

En WSL o Linux:

```bash
export AWS_PROFILE=curso
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
- LAB03: `guias/guia-iac-lab03-state-outputs-cambios.md`
- LAB04: `guias/guia-iac-lab04-data-sources-locals-nomenclatura.md`
- LAB05: `guias/guia-iac-lab05-modulos-locales.md`
- LAB06: `guias/guia-iac-lab06-backend-remoto-s3-dynamodb.md`

Para LAB01, entrar al proyecto ya incluido:

```powershell
cd terraform/iac-lab01-s3-basics
```

Antes de planificar, editar `main.tf` y cambiar el nombre del bucket por uno propio siguiendo el patron:

```text
s3-bucket-tu-account-id-tu-identidad
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

El LAB01 muestra el flujo minimo de Terraform con un bucket S3. El LAB02 agrega Lambda y empieza a separar valores variables en `terraform.tfvars`. Los laboratorios siguientes trabajan cambios, state, data sources, locals, modulos y backend remoto.

---

Proyecto educativo — Formatec Cloud Course 2026
