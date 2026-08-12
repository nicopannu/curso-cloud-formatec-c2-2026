# M3-C5 LAB02 — Monitoreo como código con Terraform

**Módulo:** M3-C5 — Monitoreo proactivo
**Duración estimada:** ~60 minutos (tarea individual)
**Branch:** `m3-c5-lab`
**Dependencia:** LAB01 completado

---

## Contexto

En LAB01 recorriste CloudWatch desde la consola: exploraste logs, creaste metric filters, armaste un dashboard y configuraste alarmas. Todo a mano, paso por paso.

Ahora vas a declarar todo eso con Terraform. El objetivo no es solo que funcione: es que quede versionado, sea repetible, y pueda aplicarse en cualquier cuenta sin depender de tu memoria.

La infraestructura (EC2s, IAM, security groups) ya está desplegada. Solo agregás los recursos de monitoreo.

---

## Arquitectura objetivo

```text
terraform/monitoreo/
├── main.tf       → metric filters + dashboard + alarmas
├── variables.tf  → student_identity, umbrales, nombres de log groups
└── outputs.tf    → nombres de alarmas creadas
```

Los recursos de monitoreo se suman a la infraestructura existente sin modificarla.

---

## Objetivos

- Escribir un spec antes de tocar código.
- Crear metric filters de CloudWatch con Terraform.
- Construir un dashboard declarativo con JSON embebido.
- Definir alarmas con condiciones precisas y tratamiento de missing data.
- Aplicar, verificar el resultado y destruir.

---

## Prerrequisitos

- Infraestructura de LAB01 desplegada (frontend + backend con logs en CloudWatch).
- Terraform ≥ 1.5.
- AWS CLI configurado con las mismas credenciales del curso.
- Leída la guía `specs/guia-de-specs.md`.

---

## Actividad 1 — Escribir el spec (10 min)

Antes de abrir Terraform, escribí un spec. No es el código. Es un documento que describe **qué** recursos vas a crear, con suficiente detalle para que alguien más (o un agente) lo implemente sin preguntarte nada.

Creá un archivo `entregables/spec-monitoreo.md`. Usá como guía `specs/guia-de-specs.md`.

Tu spec debe incluir:

1. **Objetivo:** qué problema operativo resuelve este monitoreo.
2. **Contexto:** qué infraestructura ya existe y no se toca.
3. **Recursos requeridos** (5 recursos):

   | # | Recurso | Fuente | Qué mide |
   |---|---------|--------|----------|
   | 1 | Metric filter frontend | Log group `/aws/frontend/access` | Errores 5xx de nginx |
   | 2 | Metric filter backend | Log group `/aws/backend/app` | Errores de la API |
   | 3 | Dashboard | Métricas de los filtros + CPU | 4 paneles |
   | 4 | Alarma frontend | Métrica del filtro 1 | Errores ≥ 5 en 10 min |
   | 5 | Alarma backend | Métrica del filtro 2 | Errores ≥ 1 en 5 min |

   Para cada recurso, especificá: namespace, nombre de métrica, unidad, patrón de filtro (si aplica), tipo de gráfico, estadística, umbral, datapoints, tratamiento de missing data.

4. **Restricciones:** qué NO hacer y cómo nombrar los recursos.

El spec es el entregable más importante de este lab. Un spec vago produce código que no compila. Un spec preciso produce código que funciona de una.

---

## Actividad 2 — Crear la estructura (3 min)

```bash
mkdir -p terraform/monitoreo
cd terraform/monitoreo
```

Creá tres archivos:

```bash
touch main.tf variables.tf outputs.tf
```

En `variables.tf` definí al menos:

```hcl
variable "student_identity" {
  description = "Identificador del alumno"
  type        = string
}

variable "frontend_log_group" {
  description = "Log group del frontend"
  type        = string
  default     = "/aws/frontend/access"
}

variable "backend_log_group" {
  description = "Log group del backend"
  type        = string
  default     = "/aws/backend/app"
}
```

Agregá las variables que necesites para umbrales.

El provider de AWS se configura con la región `us-east-1`. No necesita backend remoto para este lab; usá state local.

---

## Actividad 3 — Implementar metric filters (10 min)

Consultá la documentación de `aws_cloudwatch_log_metric_filter`. Vas a crear dos.

### Filter 1 — Frontend 5xx

```hcl
resource "aws_cloudwatch_log_metric_filter" "frontend_5xx" {
  name           = "${var.student_identity}-frontend-5xx"
  log_group_name = var.frontend_log_group
  pattern        = ""  # ← completar con el patrón que detecta 5xx

  metric_transformation {
    name      = "Frontend5xx"
    namespace = "BancoPatacon/Monitoreo"
    value     = "1"
    unit      = "Count"
  }
}
```

Para el patrón, usá el que probaste en LAB01. Si no lo recordás, volvé a la consola, abrí el log group y buscá una línea con error 5xx. El patrón debe matchear el status code.

Probá el patrón desde la consola (**Test pattern** en el metric filter del LAB01) antes de copiarlo a Terraform.

### Filter 2 — Backend errores

Estructura similar. Log group: `/aws/backend/app`. Métrica: `BackendErrores`. Mismo namespace.

Validá con `terraform validate` antes de continuar.

---

## Actividad 4 — Implementar el dashboard (15 min)

El recurso `aws_cloudwatch_dashboard` recibe un JSON con la definición de los widgets. Es la parte más compleja del lab. Estrategia recomendada:

1. Empezá con un solo widget. Probá `terraform apply`. Verificá que aparece en la consola.
2. Agregá los demás widgets de a uno, validando en cada paso.

Estructura del dashboard:

```hcl
resource "aws_cloudwatch_dashboard" "principal" {
  dashboard_name = "BancoPatacon-${var.student_identity}"
  dashboard_body = jsonencode({
    widgets = [
      # Widget 1: Requests frontend (NetworkIn)
      {
        type   = "metric"
        x      = 0
        y      = 0
        width  = 12
        height = 6
        properties = {
          metrics = [
            ["AWS/EC2", "NetworkIn", { stat = "Sum", period = 300 }]
          ]
          view    = "timeSeries"
          stacked = false
          region  = "us-east-1"
          title   = "Requests frontend"
          period  = 300
        }
      },
      # Widget 2: Errores 5xx frontend
      # Widget 3: Errores backend
      # Widget 4: CPU ambas instancias
    ]
  })
}
```

**Pista:** las coordenadas `x, y, width, height` usan una grilla de 24 columnas. Cada widget del ejemplo ocupa todo el ancho (12). Si querés 2 widgets por fila, usá `width: 12` para cada uno y alterná `x: 0` y `x: 12`.

Para las métricas de los filtros (widgets 2 y 3), usá:

```json
["BancoPatacon/Monitoreo", "Frontend5xx", { "stat": "Sum", "period": 300 }]
```

**Filtrá las métricas de EC2 por instancia.** `NetworkIn` y `CPUUtilization` necesitan la dimensión `InstanceId`. Usá los IDs de las instancias desplegadas por LAB01; podés obtenerlos desde la consola EC2. No presentes la suma de todas las instancias como si fuera únicamente el frontend.

---

## Actividad 5 — Implementar alarmas (10 min)

Consultá la documentación de `aws_cloudwatch_metric_alarm`.

### Alarma frontend

```hcl
resource "aws_cloudwatch_metric_alarm" "frontend_5xx" {
  alarm_name          = "Frontend5xxAlarm-${var.student_identity}"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 2
  metric_name         = "Frontend5xx"
  namespace           = "BancoPatacon/Monitoreo"
  period              = 300
  statistic           = "Sum"
  threshold           = var.frontend_5xx_threshold
  alarm_description   = "Alarma de errores 5xx en el frontend"
  treat_missing_data  = "notBreaching"
}
```

### Alarma backend

Similar. Métrica `BackendErrores`, umbral en variable. `evaluation_periods = 1`, `period = 300`.

Agregá las variables necesarias en `variables.tf`:

```hcl
variable "frontend_5xx_threshold" {
  description = "Umbral de errores 5xx para la alarma"
  type        = number
  default     = 5
}

variable "backend_error_threshold" {
  description = "Umbral de errores de backend para la alarma"
  type        = number
  default     = 1
}
```

---

## Actividad 6 — Aplicar y verificar (7 min)

```bash
terraform init
terraform fmt
terraform validate
terraform plan
terraform apply
```

Verificá en la consola AWS:

1. **CloudWatch → Metrics → Custom namespaces → `BancoPatacon/Monitoreo`.** Deberías ver `Frontend5xx` y `BackendErrores`.
2. **CloudWatch → Dashboards → `BancoPatacon-<tu-identidad>`.** Los 4 widgets deberían aparecer. Si no hay datos, ejecutá el script de tráfico unos minutos.
3. **CloudWatch → Alarms.** Ambas alarmas deberían estar en estado `OK` (o `INSUFFICIENT_DATA` si no hay tráfico todavía).

Si algo falla, corregí y volvé a aplicar. `terraform apply` es idempotente.

---

## Actividad 7 — Limpiar (5 min)

```bash
terraform destroy
```

Verificá en consola que el dashboard y las alarmas desaparecieron. Los metric filters también deberían eliminarse.

La infraestructura (EC2s) no se destruye desde este Terraform. Eso se hace desde `terraform/infra`.

---

## Entregables

- `entregables/spec-monitoreo.md` (el spec que escribiste en la Actividad 1).
- `terraform/monitoreo/main.tf` con los 5 recursos implementados.
- `terraform/monitoreo/variables.tf` con todas las variables declaradas.
- `terraform/monitoreo/outputs.tf` con los nombres de las alarmas como outputs.
- Captura del dashboard con métricas pobladas (después de generar tráfico).
- Captura de ambas alarmas en estado `OK`.
- Evidencia de `terraform destroy` completado.

---

## Troubleshooting

### El metric filter no emite datos

Verificá que el patrón matchee correctamente. Probá el patrón en la consola primero. Si el log group no tiene tráfico reciente, ejecutá el script antes de validar.

### El dashboard muestra "No data"

Las métricas de `BancoPatacon/Monitoreo` solo existen después de que el metric filter procesa logs. Si no hay tráfico, no hay métricas. Ejecutá `scripts/generar-trafico.sh` durante al menos 5 minutos y refrescá.

### La alarma queda en INSUFFICIENT_DATA

Esperado si no hay tráfico. Con tráfico activo, las métricas deberían llegar en 5 minutos. `treat_missing_data = "notBreaching"` evita falsos positivos cuando no hay datos.

### Error de permisos al crear el dashboard

El usuario IAM necesita permisos de CloudWatch (`cloudwatch:PutDashboard`, `cloudwatch:PutMetricAlarm`, `logs:PutMetricFilter`). Las credenciales del curso ya los incluyen.

---

## Criterios de evaluación — 100 puntos

| Criterio | Puntos |
|---|---|
| Spec completo con objetivo, contexto, 5 recursos y restricciones | 20 |
| Metric filters implementados con namespace y patrón correctos | 20 |
| Dashboard con 4 widgets, coordenadas y métricas correctas | 25 |
| Alarmas con umbral, evaluation_periods y missing data correctos | 20 |
| Variables declaradas, outputs funcionales | 10 |
| Limpieza confirmada | 5 |
