# Guia IaC LAB01 - Terraform sobre AWS con S3

**Modulo:** M3 - Implementacion y gestion  
**Clase:** M3-C1 - Introduccion a Infrastructure as Code  
**Branch:** `m3-c1-lab`  
**Duracion estimada:** 60 a 75 minutos  
**Tipo:** explicacion guiada + laboratorio paso a paso  
**Plataforma:** AWS  
**Herramienta:** Terraform

---

## Contexto narrativo

Hasta ahora CloudCuyo tomo decisiones de arquitectura: migrar workloads a AWS, mejorar disponibilidad, separar responsabilidades y probar nuevos modelos de ejecucion como contenedores y serverless.

El problema de esta clase aparece despues de tomar esas decisiones: si cada ambiente se arma a mano, la arquitectura no es repetible. Puede funcionar una vez, pero no hay garantia de que el siguiente ambiente quede igual, que otro equipo lo pueda revisar o que los cambios sean trazables.

En este laboratorio, CloudCuyo empieza a tratar la infraestructura como software. El ejercicio usa un recurso simple y barato, un bucket S3 privado, para aprender el ciclo completo de Terraform: codigo, provider, variables, plan, estado, recursos reales, cambios y limpieza.

Mensaje para abrir la actividad:

> Si la infraestructura se crea a mano, no es repetible. Si no es repetible, no es confiable.

---

## Objetivos de aprendizaje

Al finalizar, el alumno deberia poder:

1. Explicar que problema resuelve Infrastructure as Code frente a cambios manuales por consola.
2. Reconocer las piezas basicas de Terraform: provider, resource, variable, local, output y state.
3. Ejecutar el flujo basico: `init`, `fmt`, `validate`, `plan`, `apply` y `destroy`.
4. Leer un `terraform plan` antes de aprobar cambios reales.
5. Entender por que `terraform.tfstate` es critico y sensible.
6. Aplicar controles minimos de seguridad: no secretos, bloqueo publico, cifrado, tags y limpieza.
7. Diferenciar validacion local, planificacion contra AWS y modificacion real de recursos.

---

## Arquitectura del ejercicio

```text
Repositorio Git
  |
  | archivos .tf
  v
Terraform CLI
  |
  | init / fmt / validate / plan / apply
  v
Provider AWS
  |
  v
AWS S3 Bucket privado
  |-- Public Access Block
  |-- Versioning enabled
  |-- Server-side encryption AES256
  |-- Tags comunes

Terraform local state
  |-- terraform.tfstate
```

Decision de alcance: usamos S3 porque permite explicar IaC sin sumar VPC, subnets, EC2, ALB o IAM complejo. El foco de la clase es el metodo de trabajo, no construir una arquitectura grande.

---

## Alcance del lab

### Obligatorio

- Revisar la estructura del proyecto Terraform.
- Ejecutar `terraform init`, `terraform fmt`, `terraform validate` y `terraform plan`.
- Leer el plan y explicar que cambios propone Terraform.
- Identificar que informacion queda en el estado.
- Entregar evidencia del plan y una explicacion corta de los componentes.

### Con autorizacion docente

- Ejecutar `terraform apply` en la cuenta AWS de laboratorio.
- Revisar outputs.
- Ejecutar un cambio controlado y leer el nuevo plan.
- Ejecutar `terraform destroy` y verificar limpieza.

### Opcional / demostracion docente

- Modificar un tag manualmente en AWS y discutir drift.
- Conversar sobre estado remoto, locking, ambientes y CI/CD.
- Comparar este laboratorio con una infraestructura mayor: VPC + EC2 + ALB.

---

## Pre-requisitos

En la terminal del alumno o del docente:

- Terraform instalado.
- AWS CLI instalado si se va a validar identidad o usar cuenta real.
- Credenciales AWS configuradas solo para una cuenta sandbox/laboratorio.
- Permisos para crear, consultar y eliminar buckets S3.
- Git instalado.

Verificaciones:

```bash
terraform version
aws --version
```

Validacion no destructiva de identidad AWS:

```bash
aws sts get-caller-identity
```

Si se usa un perfil especifico:

```bash
AWS_PROFILE=curso aws sts get-caller-identity
```

Nota docente: `sts get-caller-identity` no crea recursos. `terraform apply` y `terraform destroy` si modifican AWS.

---

## Preparacion del repositorio

Clonar y cambiar a la branch del laboratorio:

```bash
git clone https://github.com/nicopannu/curso-cloud-formatec-c2-2026.git
cd curso-cloud-formatec-c2-2026
git checkout m3-c1-lab
```

Entrar al proyecto Terraform:

```bash
cd terraform/iac-lab01-s3-basics
```

Estructura esperada:

```text
terraform/iac-lab01-s3-basics/
  versions.tf
  providers.tf
  variables.tf
  main.tf
  outputs.tf
  terraform.tfvars.example
  README.md
```

---

## Actividad 1 - Leer el codigo antes de ejecutar

Abrir los archivos `.tf` y ubicar:

1. `versions.tf`: version requerida de Terraform y providers.
2. `providers.tf`: region AWS y `default_tags`.
3. `variables.tf`: parametros configurables.
4. `main.tf`: recursos AWS declarados.
5. `outputs.tf`: datos que Terraform mostrara despues del apply.

Preguntas para el grupo:

- Que recurso principal se va a crear?
- Donde aparece la region?
- Que valores podrian cambiar entre ambientes?
- Donde se declara que el bucket no debe ser publico?
- Que parte del codigo ayuda a identificar costos y ownership?

Checkpoint: antes de correr Terraform, el alumno debe poder señalar en el codigo que recurso se va a crear y que controles de seguridad tendra.

---

## Actividad 2 - Inicializar Terraform

Ejecutar:

```bash
terraform init -backend=false
```

Explicacion:

- `init` prepara el directorio de trabajo.
- Descarga los providers necesarios.
- `-backend=false` evita configurar backend remoto; para este primer lab usamos estado local.
- Se genera o usa `.terraform.lock.hcl`, que fija versiones de providers para reproducibilidad.

Checkpoint:

- Que diferencia hay entre instalar Terraform y descargar providers?
- Por que el provider AWS no viene embebido dentro del binario de Terraform?

---

## Actividad 3 - Formato y validacion

Ejecutar:

```bash
terraform fmt -check
terraform validate
```

Si `fmt -check` marca cambios necesarios, ejecutar:

```bash
terraform fmt
terraform fmt -check
```

Explicacion:

- `fmt` estandariza estilo del codigo.
- `validate` revisa sintaxis, referencias internas y esquema de providers.
- `validate` no confirma que la arquitectura sea segura ni que el cambio sea deseable.

Checkpoint:

- Por que `validate` puede pasar aunque la decision arquitectonica sea mala?
- Que tipo de errores detecta y que tipo de errores no detecta?

---

## Actividad 4 - Preparar variables

El lab ya tiene defaults seguros. Si se quiere personalizar:

```bash
cp terraform.tfvars.example terraform.tfvars
```

Editar `terraform.tfvars`:

```hcl
aws_region   = "us-east-1"
project_name = "cloudcuyo-iac"
environment  = "lab"
owner        = "formatec"
```

Reglas:

- No guardar secretos en `terraform.tfvars`.
- No commitear `terraform.tfvars`.
- Mantener nombres en minusculas para S3.
- Usar cuenta de laboratorio, no cuenta productiva.

Checkpoint:

- Que valores conviene parametrizar?
- Que valores no deberian estar en un repositorio?

---

## Actividad 5 - Leer el plan antes de aplicar

Ejecutar:

```bash
terraform plan
```

Con perfil AWS especifico:

```bash
AWS_PROFILE=curso terraform plan
```

Durante la lectura del plan, marcar:

- acciones `+ create`;
- recursos a crear;
- atributos conocidos antes del apply;
- atributos conocidos despues del apply;
- tags aplicados;
- dependencias implicitas entre recursos.

Recursos esperados:

- `random_id.bucket_suffix`
- `aws_s3_bucket.lab`
- `aws_s3_bucket_public_access_block.lab`
- `aws_s3_bucket_versioning.lab`
- `aws_s3_bucket_server_side_encryption_configuration.lab`

Preguntas para el grupo:

- Terraform va a crear, modificar o destruir?
- Por que aparece un sufijo aleatorio para el bucket?
- Que atributos todavia no conoce Terraform antes de crear el recurso?
- Que linea del plan revisarian con mas cuidado en un ambiente real?
- Que pasaria si el plan mostrara `destroy` en produccion?

Checkpoint: nadie deberia ejecutar `apply` sin poder explicar el plan.

---

## Actividad 6 - Aplicar cambios reales en AWS

Ejecutar solo si el docente autoriza el uso de la cuenta AWS de laboratorio.

```bash
terraform apply
```

Con perfil AWS especifico:

```bash
AWS_PROFILE=curso terraform apply
```

Cuando Terraform pida confirmacion, escribir:

```text
yes
```

Luego revisar outputs:

```bash
terraform output
```

Evidencia esperada:

- nombre final del bucket;
- ARN del bucket;
- region usada;
- tags comunes.

Explicacion docente:

`apply` no es un paso administrativo. Es el momento en que el codigo modifica infraestructura real. Por eso en equipos profesionales suele requerir revision, aprobacion y pipeline.

---

## Actividad 7 - Entender el estado local

Listar archivos generados:

```bash
ls -la
```

Identificar:

- `.terraform/`
- `.terraform.lock.hcl`
- `terraform.tfstate`
- posible `terraform.tfstate.backup`

Preguntas:

- Que recurso real queda asociado al estado?
- Por que `terraform.tfstate` es sensible?
- Que problema aparece si dos personas aplican desde estados locales distintos?
- Que cambiaria en un equipo real? Estado remoto y locking.

Checkpoint: el alumno debe poder explicar que Terraform no consulta Git para saber que administra; usa el state.

---

## Actividad 8 - Cambio controlado

Cambiar una variable simple, por ejemplo `owner`, en `terraform.tfvars`:

```hcl
owner = "equipo-a"
```

Ejecutar:

```bash
terraform plan
```

Con perfil:

```bash
AWS_PROFILE=curso terraform plan
```

Objetivo:

- ver que Terraform detecta diferencia entre codigo, variables y estado;
- distinguir update de replacement;
- discutir si el cambio es seguro;
- reforzar que el plan se revisa antes del apply.

Preguntas:

- Este cambio reemplaza el bucket o actualiza metadatos?
- Que indica el simbolo `~` en el plan?
- Aplicarian este cambio automaticamente en produccion?

---

## Actividad 9 - Drift opcional

Solo como demostracion docente:

1. Cambiar manualmente un tag del bucket desde la consola AWS.
2. Ejecutar:

```bash
terraform plan
```

3. Observar que Terraform intenta volver al estado declarado en codigo.

Discusion:

- Que riesgo tienen los cambios manuales?
- Cuando un cambio manual puede ser una emergencia valida?
- Como se deberia registrar luego ese cambio en codigo?

---

## Actividad 10 - Limpieza

Si se ejecuto `apply`, cerrar con:

```bash
terraform destroy
```

Con perfil:

```bash
AWS_PROFILE=curso terraform destroy
```

Confirmar con `yes`.

Luego verificar que el bucket ya no existe:

```bash
terraform state list
```

Opcional con AWS CLI, reemplazando el nombre por el output visto antes:

```bash
aws s3api head-bucket --bucket NOMBRE_DEL_BUCKET
```

Si el bucket fue destruido, `head-bucket` debe fallar porque ya no existe o no es accesible.

Cierre docente:

- En laboratorios, limpiar recursos es parte de la practica.
- En produccion, `destroy` debe estar restringido, revisado y auditado.

---

## Troubleshooting

| Problema | Causa probable | Accion |
|---|---|---|
| `terraform: command not found` | Terraform no instalado o no esta en PATH | Instalar Terraform o revisar PATH |
| `No valid credential sources found` | No hay credenciales AWS | Configurar perfil AWS o variables de entorno |
| `AccessDenied` | Permisos insuficientes | Validar IAM de la cuenta laboratorio |
| `BucketAlreadyExists` | Nombre global S3 duplicado | Revisar `random_id` o cambiar `project_name` |
| `fmt -check` falla | Formato distinto al estandar | Ejecutar `terraform fmt` |
| `destroy` falla con bucket no vacio | Hay objetos dentro del bucket | Vaciar bucket y repetir destroy |

---

## Entregables

Cada alumno o grupo debe entregar:

1. Salida o captura de `terraform validate` exitoso.
2. Fragmento del `terraform plan` indicando recursos a crear.
3. Tabla corta con `provider`, `resource`, `variable`, `output` y `state` explicados con sus palabras.
4. Respuesta breve: por que el estado de Terraform no se comparte informalmente?
5. Si se hizo `apply`: nombre del bucket creado, outputs y evidencia de `destroy`.
6. Una decision de seguridad identificada en el codigo, por ejemplo bloqueo publico, cifrado o tags.

---

## Criterios de evaluacion

| Criterio | Esperado |
|---|---|
| Comprension de IaC | Explica por que el codigo mejora repetibilidad, revision y trazabilidad |
| Lectura de Terraform | Identifica provider, recursos, variables, outputs y state |
| Interpretacion del plan | Distingue crear, modificar y destruir antes de aplicar |
| Seguridad basica | Reconoce bloqueo publico, cifrado, tags, no secretos y cuenta sandbox |
| Operacion responsable | No ejecuta apply sin autorizacion y limpia recursos si los creo |
| Justificacion tecnica | Explica trade-offs entre lab simple y uso real en equipos |

---

## Anti-patrones a evitar

- Ejecutar `apply` sin leer el plan.
- Usar una cuenta productiva para una demo.
- Subir `terraform.tfstate`, `terraform.tfvars` o secretos al repositorio.
- Pensar que `validate` confirma que la arquitectura es segura.
- Crear recursos por consola y olvidarse de reflejarlos en codigo.
- No ejecutar `destroy` al final del laboratorio.
- Copiar comandos sin entender que recurso real modifican.

---

## Cierre para discusion

Preguntas finales:

1. Que diferencia hay entre crear el bucket por consola y declararlo en Terraform?
2. Que parte del ejercicio representa el estado deseado?
3. Que parte representa la realidad en AWS?
4. Que pasaria si alguien modifica el bucket manualmente?
5. Como cambiaria este lab si trabajaran tres personas sobre la misma infraestructura?
6. Que deberia pasar antes de ejecutar `apply` en una empresa?

Takeaway:

> Terraform no es importante porque crea un bucket. Es importante porque obliga a que el cambio de infraestructura sea visible, revisable, repetible y limpiable.
