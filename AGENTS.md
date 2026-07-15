# AGENTS.md — Formatec Cloud 2026 · M3-C1 IaC

Contrato de trabajo para agentes de IA que colaboran con el material o acompañan la realización de los laboratorios.

## Qué es este repo

Repositorio del curso **Arquitectura e Ingeniería Cloud | C2** (Formatec Cloud 2026).

- **Módulo:** M3 — Clase 1: Infrastructure as Code con Terraform sobre AWS
- **Branch del material:** `m3-c1-lab`
- **Profesor:** Nicolas Pannucio
- **Idea central:** la infraestructura manual no es repetible ni confiable; Terraform la declara, versiona y reproduce.

Este es principalmente un **repositorio fuente de guías educativas**, no un repositorio de soluciones terminadas. Contiene las instrucciones que marcan el alcance, el orden de aprendizaje, los checkpoints y los entregables de cada LAB.

El único proyecto Terraform precargado es el punto de partida de LAB01. LAB02–LAB06 deben construirse siguiendo sus guías. No agregues soluciones completas de esos laboratorios al material publicado salvo que el usuario pida explícitamente una solución de referencia.

Los alumnos clonan el material del curso y entregan su trabajo en un **repositorio personal** separado. Cuando aparezcan carpetas no versionadas, trátalas como trabajo local del usuario: no las borres, no las sobrescribas y no las uses como fuente de verdad sin autorización.

## Estructura del repositorio

```text
.
├── README.md                          # Índice general, setup y flujo de entrega
├── AGENTS.md                          # Este archivo
├── .gitignore                         # Excluye state, .terraform/, credenciales, tfvars
├── guias/
│   ├── guia-iac-lab01-terraform-s3.md
│   ├── guia-iac-lab02-terraform-lambda.md
│   ├── guia-iac-lab03-state-outputs-cambios.md
│   ├── guia-iac-lab04-data-sources-locals-nomenclatura.md
│   ├── guia-iac-lab05-modulos-locales.md
│   └── guia-iac-lab06-backend-remoto-s3-dynamodb.md
└── terraform/
    └── iac-lab01-s3-basics/           # Único proyecto Terraform incluido en el repo del curso
        ├── versions.tf
        ├── providers.tf
        ├── main.tf
        └── README.md
```

Los laboratorios LAB02–LAB06 se crean **durante la guía** por el alumno. No están precargados en este repo.

## Progresión de laboratorios

| LAB | Guía | Proyecto | Conceptos nuevos |
|-----|------|----------|------------------|
| LAB01 | `guias/guia-iac-lab01-terraform-s3.md` | `terraform/iac-lab01-s3-basics/` | init, fmt, validate, plan, apply, state, destroy |
| LAB02 | `guias/guia-iac-lab02-terraform-lambda.md` | Creado por el alumno | Lambda, variables, `terraform.tfvars`, outputs, AWS CLI invoke |
| LAB03 | `guias/guia-iac-lab03-state-outputs-cambios.md` | Continuación LAB02 | Outputs, state, cambios controlados, lectura de planes |
| LAB04 | `guias/guia-iac-lab04-data-sources-locals-nomenclatura.md` | Creado por el alumno | Data sources, locals, nomenclatura, tags comunes |
| LAB05 | `guias/guia-iac-lab05-modulos-locales.md` | Creado por el alumno | Módulos locales, inputs, outputs, reutilización |
| LAB06 | `guias/guia-iac-lab06-backend-remoto-s3-dynamodb.md` | Creado por el alumno | Backend remoto S3 + DynamoDB locking |

Antes de proponer código para un LAB, leer la guía correspondiente en `guias/`. Las guías definen el alcance pedagógico y el orden de introducción de conceptos.

## Identificar el modo de trabajo

Antes de actuar, determina cuál de estos modos solicita el usuario.

### Modo A — Mantener el material del curso

Se usa cuando el usuario pide crear, revisar o corregir una guía.

- Trabajar sobre `README.md`, `guias/` o el proyecto de referencia indicado.
- Antes de editar, listar los archivos y el objetivo de cada cambio.
- Escribir para el alumno: instrucciones directas, técnicas y ejecutables.
- Mantener narrativa, objetivos, actividades, checkpoints, entregables y criterios de evaluación cuando correspondan.
- Explicar decisiones y trade-offs sin convertir la guía en notas internas para el profesor.
- No crear carpetas de solución para LAB02–LAB06 salvo pedido explícito.
- No ejecutar recursos AWS por defecto. Una validación de documentación no autoriza `plan`, `apply` ni `destroy` contra la cuenta.

### Modo B — Acompañar a un alumno a realizar un LAB

Se usa cuando el usuario pide “hacer”, “resolver” o “seguir” un laboratorio.

- Leer primero la guía completa del LAB solicitado.
- No modificar la guía para adaptar el ejercicio a una solución diferente.
- Crear archivos solamente en la carpeta de trabajo indicada por el usuario.
- Construir el laboratorio por etapas; no volcar todos los archivos y comandos de una sola vez sin explicación.
- Respetar exactamente el concepto nuevo de esa etapa y reutilizar lo aprendido en etapas anteriores.
- Si la solicitud es clara, comenzar con la primera etapa sin pedir confirmaciones innecesarias. Las operaciones AWS con efectos reales conservan sus reglas de autorización.

Si el modo no está explícito, indica brevemente cuál asumiste antes de trabajar.

## Convenciones Terraform del curso

### Versiones y providers

- Terraform `>= 1.6.0`
- Provider AWS `hashicorp/aws ~> 5.0`
- Provider `archive ~> 2.4` (desde LAB02, para empaquetar Lambda)

### Región

- Región por defecto: **`us-east-1`**
- En LAB01 la región está hardcodeada en `providers.tf`
- Desde LAB02 la región viene de la variable `aws_region` en `terraform.tfvars`

### Nomenclatura de recursos

Patrón general (LAB04 en adelante):

```hcl
locals {
  name_prefix = "${var.project}-${var.environment}-${var.student_identity}"
  bucket_name = "${local.name_prefix}-${data.aws_caller_identity.current.account_id}"
}
```

Variables típicas en `terraform.tfvars`:

```hcl
aws_region       = "us-east-1"
project          = "formatec"
environment      = "lab"
student_identity = "tu-identidad"
```

LAB01 usa un nombre directo en `main.tf` que el alumno debe personalizar:

```text
s3-bucket-<account-id>-<identidad>
```

Los nombres de bucket S3 deben ser **globalmente únicos**.

### Tags comunes (LAB04+)

```hcl
common_tags = {
  Project     = var.project
  Environment = var.environment
  Owner       = var.student_identity
  Course      = "formatec"
  ManagedBy   = "terraform"
}
```

### Estructura de archivos por etapa

| Etapa | Archivos esperados |
|-------|-------------------|
| LAB01 | `versions.tf`, `providers.tf`, `main.tf` |
| LAB02+ | + `variables.tf`, `terraform.tfvars`, `outputs.tf` |
| LAB04+ | + `data.tf`, `locals.tf` |
| LAB05+ | + carpeta `modules/` con módulos locales |
| LAB06 | + `backend.tf` con bloque `backend "s3"` |

### Flujo de comandos

```bash
terraform init -backend=false   # LAB01–LAB05 (sin backend remoto)
terraform fmt
terraform validate
terraform plan
terraform apply                 # Solo con autorización y cuenta de laboratorio
terraform destroy               # Limpiar al terminar
```

En LAB06 se migra a backend remoto; ahí `terraform init` configura S3 + DynamoDB.

## Entorno AWS

- Perfil de laboratorio típico: **`curso`**
- Configuración: `aws configure --profile curso`
- Activar en la sesión:
  - PowerShell: `$env:AWS_PROFILE="curso"`
  - Bash/WSL: `export AWS_PROFILE=curso`
- Verificar identidad: `aws sts get-caller-identity`

**No ejecutar `terraform apply` ni `terraform destroy` sin confirmación explícita del usuario.** Estos comandos crean o eliminan recursos reales en AWS.

## Seguridad — nunca commitear

Respetar `.gitignore`. Nunca agregar al repositorio:

- Credenciales AWS, claves `.pem`, archivos `.env`
- `terraform.tfstate`, `*.tfstate.*`, `.terraform/`
- `terraform.tfvars` (contiene identidad del alumno; sí se permiten `*.tfvars.example`)
- Carpetas de IDE/IA (`.cursor/`, `.vscode/`, etc.) ya excluidas
- Scripts con IDs sensibles (`aws-ids.sh`, `aws-ids.ps1`)

Si un alumno pide commitear credenciales o state, rechazar y explicar por qué.

## Repositorio personal del alumno

Los entregables van en un repo aparte, no en este repo del curso:

```text
curso-cloud-formatec-<nombreapellido>-c2-2026/
├── lab01/
├── lab02/
├── lab03/
├── lab04/
├── lab05/
└── lab06/
```

- Branch de entrega: `m3-c1-lab`
- Commits descriptivos por lab, por ejemplo: `Agregar entrega LAB01 M3 C1`

## Protocolo de acompañamiento pedagógico

El objetivo no es solamente producir HCL válido. El alumno debe entender qué está declarando, por qué se incorpora en ese momento y cómo comprobarlo.

### Antes de crear código

1. Identificar el LAB activo y citar la guía que se va a seguir.
2. Revisar los archivos existentes antes de proponer cambios.
3. Resumir en pocas líneas:
   - objetivo de la etapa;
   - arquitectura o recurso AWS involucrado;
   - concepto Terraform nuevo;
   - archivos que se crearán o modificarán.
4. Distinguir qué se reutiliza del LAB anterior y qué se incorpora ahora.

### Al crear cada archivo

No te limites a pegar código. Presenta cada archivo con esta secuencia:

1. **Qué archivo se crea:** ruta y responsabilidad.
2. **Por qué existe:** problema que resuelve dentro del proyecto.
3. **Qué declara:** bloques y referencias importantes.
4. **Qué representa en AWS:** recurso real, dato consultado o configuración local.
5. **De qué depende:** variables, provider, archivo fuente, rol o recurso previo.
6. **Qué debería observarse:** resultado esperado en `validate`, `plan`, outputs o AWS CLI.

Ejemplo de nivel de explicación esperado:

> `providers.tf` configura el provider AWS en `us-east-1`. No crea infraestructura por sí mismo: indica a Terraform con qué API y región debe trabajar. Las credenciales se obtienen del perfil AWS activo y nunca se escriben en el archivo.

Después de explicar, crea o modifica el archivo. Mantén cambios pequeños para que el alumno pueda relacionarlos con el plan siguiente.

### Ciclo de validación por etapa

Después de una etapa de código:

1. Ejecutar `terraform fmt`.
2. Ejecutar `terraform validate` y mostrar el resultado real.
3. Ejecutar `terraform plan` únicamente cuando el entorno AWS esté configurado y el usuario haya autorizado trabajar con la cuenta de laboratorio.
4. Traducir el plan a lenguaje claro:
   - cantidad de recursos a crear, cambiar y destruir;
   - significado de `+`, `~`, `-` y `-/+` cuando aparezcan;
   - nombres reales y región;
   - reemplazos o riesgos relevantes.
5. Formular un checkpoint breve que el alumno pueda responder antes de seguir.

No inventes salidas de Terraform o AWS. Distingue siempre entre comando sugerido, comando ejecutado y resultado observado.

### Apply, verificación y limpieza

- `terraform apply` requiere autorización explícita del usuario.
- Antes del apply, resumir nuevamente qué recursos reales se crearán y si pueden generar costo.
- Después del apply, verificar con outputs, state y AWS CLI; `Apply complete` no demuestra por sí solo que el recurso funciona como se esperaba.
- `terraform destroy` requiere una segunda autorización explícita.
- Después del destroy, comprobar con AWS CLI que los recursos desaparecieron y revisar residuos que Terraform puede no administrar, como log groups creados durante una invocación.

### Calidad pedagógica de las respuestas

- Usar español técnico y directo cuando el usuario escribe en español.
- Explicar una decisión antes de introducir sintaxis nueva.
- Relacionar Terraform con el recurso AWS real, sin presentar HCL como un fin en sí mismo.
- Hacer explícitos los trade-offs de seguridad, costo, estado, repetibilidad y operación cuando sean relevantes.
- Diferenciar claramente `resource` vs `data`, `variable` vs `local`, `plan` vs `apply` y state local vs remoto.
- Referenciar la guía con su ruta, por ejemplo `guias/guia-iac-lab03-state-outputs-cambios.md`.
- Ante un error, trabajar sobre el mensaje real del CLI o Terraform; no simular una corrección exitosa.

### Límites

- No adelantar conceptos de labs posteriores. Por ejemplo, no introducir variables en LAB01 ni módulos en LAB02.
- No crear pipelines CI/CD, Kubernetes ni infraestructura fuera del alcance de M3-C1.
- No reemplazar el recorrido de aprendizaje por un script que genere o despliegue todo automáticamente.
- No asumir permisos de administrador en AWS.
- No modificar guías cuando el pedido es completar un ejercicio.
- No refactorizar un laboratorio completo si un cambio focalizado resuelve el problema.
- No commitear ni pushear cambios salvo que el usuario lo pida explícitamente.

## Referencias rápidas

- Índice y setup: `README.md`
- Proyecto LAB01: `terraform/iac-lab01-s3-basics/README.md`
- Documentación Terraform: https://developer.hashicorp.com/terraform/docs
- Documentación AWS Provider: https://registry.terraform.io/providers/hashicorp/aws/latest/docs

---

Proyecto educativo — Formatec Cloud Course 2026
