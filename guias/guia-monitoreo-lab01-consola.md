# M3-C5 LAB01 — Del spec al monitoreo por consola

**Módulo:** M3-C5 — Monitoreo proactivo
**Duración estimada:** 90 minutos (guiado en clase)
**Branch:** `m3-c5-lab`
**Formato:** construcción guiada + operación en AWS

---

## Contexto

Banco Patacon tiene un frontend web y un backend que procesa transferencias. El código de infraestructura ya está declarado con Terraform, pero todavía falta una forma repetible de desplegarlo.

En este laboratorio vas a construir, con ayuda de un agente, un workflow manual de GitHub Actions a partir de un spec. Cuando el workflow esté listo, lo vas a ejecutar para desplegar la infraestructura. Recién después vas a comenzar el recorrido de monitoreo:

```text
spec
→ plan del agente
→ workflow de GitHub Actions
→ Terraform apply
→ frontend + backend operando
→ tráfico
→ logs
→ métricas
→ dashboard
→ alarmas
```

El workflow es el punto de continuidad con la clase anterior. El objetivo principal del lab es monitorear el sistema desplegado, no aprender sintaxis de GitHub Actions en profundidad.

---

## Arquitectura objetivo

```mermaid
flowchart LR
  SPEC[Spec] --> AGENT[Agente en Plan Mode]
  AGENT --> WF[GitHub Actions]
  WF --> TF[Terraform infra]
  TF --> FE[EC2 Frontend nginx]
  TF --> BE[EC2 Backend Flask]
  FE --> FLOG[/aws/frontend/access]
  BE --> BLOG[/aws/backend/app]
  FLOG --> CW[CloudWatch]
  BLOG --> CW
  CW --> MF[Metric filters]
  CW --> DASH[Dashboard]
  CW --> ALARM[Alarmas]
```

### Componentes

| Componente | Responsabilidad |
|---|---|
| Terraform | Declara frontend, backend, IAM y bootstrap del CloudWatch Agent |
| GitHub Actions | Ejecuta `fmt`, `init`, `validate`, `plan`, `apply` o `destroy` |
| Frontend | Nginx con página de estado de Banco Patacon; endpoint `/server-error` para simular HTTP 500 |
| Backend | API Flask con `/health` y `/transferir`; registra eventos JSON |
| CloudWatch Logs | Recibe access logs del frontend y logs de aplicación del backend |
| Consola CloudWatch | En LAB01 crea metric filters, dashboard y alarmas manualmente |

---

## Objetivos

- Escribir y revisar un spec técnico para un workflow.
- Usar Plan Mode para pedirle a un agente una propuesta antes de editar.
- Construir un workflow manual que despliegue Terraform.
- Verificar una arquitectura real antes de monitorearla.
- Generar tráfico y observar logs.
- Crear por consola metric filters, dashboard y alarmas.
- Interpretar un incidente simulado.

---

## Prerrequisitos

- Repositorio abierto en Cursor.
- Archivo `specs/guia-de-specs.md` leído.
- Archivo `specs/lab01-workflow-spec-guia.md` disponible.
- Terraform en `terraform/infra/` entendido a nivel general.
- Acceso al repositorio de GitHub.
- La cuenta del curso y sus credenciales de Actions están preparadas por el profesor.

No agregues credenciales al repositorio. No ejecutes `terraform apply` desde tu máquina salvo que el profesor lo indique.

---

## Actividad 1 — Leer el contexto y la arquitectura (5 min)

Antes de usar el agente, explorá:

```text
README.md
specs/guia-de-specs.md
specs/lab01-workflow-spec-guia.md
terraform/infra/main.tf
terraform/infra/variables.tf
terraform/infra/outputs.tf
```

Identificá:

- qué recursos crea Terraform;
- qué logs debería producir cada instancia;
- qué outputs necesitás para probar el sistema;
- qué recursos todavía no existen: metric filters, dashboard y alarmas.

### Checkpoint 1

Podés explicar esta diferencia:

> Terraform ya declara la infraestructura. El workflow todavía debe declarar cómo se ejecuta Terraform. El monitoreo se construirá después, desde la consola.

---

## Actividad 2 — Construir el spec del workflow (10 min)

Abrí `specs/lab01-workflow-spec-guia.md`.

El documento no es el workflow terminado. Es una guía para construirlo. Revisá que incluya:

- trigger manual;
- acciones `apply` y `destroy`;
- credenciales desde GitHub Secrets;
- directorio `terraform/infra`;
- validación antes de aplicar;
- outputs al finalizar;
- ausencia de recursos de monitoreo en el workflow.

Completá o ajustá el spec con las decisiones de la clase: nombre de secrets, región, identidad de despliegue y mecanismo para conservar el mismo identificador en `apply` y `destroy`.

---

## Actividad 3 — Pedir un plan al agente (10 min)

En Cursor Plan Mode, usá el prompt incluido al final de `specs/lab01-workflow-spec-guia.md`.

El agente debe responder con:

1. archivos que va a crear o modificar;
2. pasos del workflow;
3. secrets e inputs;
4. riesgos o ambigüedades;
5. validaciones.

No aceptes la implementación todavía. Revisá el plan con estas preguntas:

- ¿El workflow se ejecuta solo manualmente?
- ¿Distingue `apply` de `destroy`?
- ¿Valida Terraform antes de crear recursos?
- ¿Usa `actions/checkout@v4`, `setup-terraform@v3` y credenciales configuradas correctamente?
- ¿Evita crear dashboards o alarmas antes de tiempo?

Cuando el plan sea correcto, pedile al agente que implemente únicamente lo aprobado.

### Checkpoint 2

El archivo `.github/workflows/deploy-infra.yml` existe, pero todavía no lo ejecutes si no revisaste su diff.

---

## Actividad 4 — Validar y ejecutar el workflow (10 min)

Revisá el workflow y validá Terraform:

```bash
terraform -chdir=terraform/infra init -backend=false
terraform -chdir=terraform/infra validate
git diff -- .github/workflows/deploy-infra.yml
```

El repositorio de la clase debe tener configurada la variable `TF_STATE_BUCKET` con el bucket S3 autorizado para el state. No escribas ese nombre dentro del código si el profesor no lo indicó.

El profesor ejecuta **Actions → Deploy infrastructure → Run workflow → apply**, completando también `student_identity` con el identificador elegido para la clase.

Observá:

- checkout;
- configuración de credenciales;
- `terraform fmt`, `init`, `validate` y `plan`;
- `terraform apply`;
- outputs de frontend y backend.

Guardá las URLs que aparecen en los outputs.

---

## Actividad 5 — Verificar la arquitectura desplegada (5 min)

Desde una terminal:

```bash
curl <FRONTEND_URL>
curl <BACKEND_URL>/health
```

El frontend debe devolver la página de Banco Patacon. El backend debe devolver un estado `ok`.

Si el servicio todavía no responde, esperá el bootstrap de EC2 y repetí. No avances a CloudWatch sin comprobar primero que la aplicación está viva.

### Checkpoint 3

Tenés evidencia de:

- frontend HTTP 200;
- backend `/health` exitoso;
- outputs de Terraform guardados;
- dos EC2s activas.

---

## Actividad 6 — Generar tráfico e inspeccionar logs (10 min)

Ejecutá:

```bash
chmod +x scripts/generar-trafico.sh
./scripts/generar-trafico.sh <FRONTEND_URL> <BACKEND_URL> 120
```

El script genera tráfico normal y, cada aproximadamente 30 segundos, cinco requests a `/server-error`, que devuelve HTTP 500. El backend produce transferencias exitosas y errores simulados.

En paralelo, abrí **CloudWatch → Log groups**:

| Log group | Qué observar |
|---|---|
| `/aws/frontend/access` | método, path, status code y tamaño de respuesta |
| `/aws/backend/app` | JSON con `status`, `endpoint`, `monto` y `duration_ms` |

### Checkpoint 4

Podés señalar en un log real:

- un request correcto;
- un request fallido;
- el campo que luego usará el metric filter.

---

## Actividad 7 — Crear métricas desde logs (10 min)

Desde **CloudWatch → Log groups → Metric filters**:

### Frontend 5xx

Usá el patrón que detecta status 500–599 en el access log:

```text
[ip, user, timestamp, tz, request, status=5*, bytes, referer, agent]
```

Creá la métrica:

- namespace: `BancoPatacon/Monitoreo`;
- name: `Frontend5xx`;
- value: `1`;
- unit: `Count`.

### Backend errores

Sobre `/aws/backend/app`, usá un patrón JSON que encuentre:

```text
{ $.status = "error" }
```

Creá `BackendErrores` en el mismo namespace, con valor `1` y unidad `Count`.

Probá ambos patrones con **Test pattern** antes de guardar.

### Checkpoint 5

En **CloudWatch → Metrics → Custom namespaces** aparecen `Frontend5xx` y `BackendErrores`.

---

## Actividad 8 — Dashboard y alarmas (15 min)

Creá un dashboard `BancoPatacon-<tu-identidad>` con cuatro widgets:

1. `AWS/EC2 → NetworkIn`, filtrado por `InstanceId` del frontend, Sum, 5 minutos: volumen de red del frontend.
2. `BancoPatacon/Monitoreo → Frontend5xx`, Sum, 5 minutos.
3. `BancoPatacon/Monitoreo → BackendErrores`, Sum, 5 minutos.
4. `AWS/EC2 → CPUUtilization`, Average, 5 minutos, frontend y backend.

Usá las métricas para responder preguntas, no para llenar espacio:

- ¿hay tráfico?
- ¿hay errores visibles?
- ¿hay errores en la API?
- ¿hay saturación?

Creá dos alarmas, sin SNS:

| Alarma | Condición | Evaluación | Missing data |
|---|---|---|---|
| Frontend5xxAlarm | `Frontend5xx >= 5` | 2 de 2 períodos de 5 min | `notBreaching` |
| BackendErroresAlarm | `BackendErrores >= 1` | 1 de 1 período de 5 min | `notBreaching` |

### Checkpoint 6

El dashboard existe y ambas alarmas están en `OK` o `INSUFFICIENT_DATA` antes del incidente.

---

## Actividad 9 — Simular e investigar un incidente (10 min)

Ejecutá el tráfico durante 10 minutos:

```bash
./scripts/generar-trafico.sh <FRONTEND_URL> <BACKEND_URL> 600
```

Observá:

- los picos de `Frontend5xx`;
- los errores de `BackendErrores`;
- el cambio de estado de las alarmas;
- los timestamps de los eventos en Logs Insights.

Consultá el frontend:

```text
fields @timestamp, @message
| filter @message like /500/
| sort @timestamp desc
| limit 20
```

Consultá el backend:

```text
fields @timestamp, @message
| filter @message like /"status": "error"/
| sort @timestamp desc
| limit 20
```

Respondé:

1. ¿Qué señal detectó primero el problema?
2. ¿Por qué la alarma backend tiene una evaluación más rápida?
3. ¿Qué diferencia hay entre alarma y alerta operativa?
4. ¿Qué información aportan los logs que no aparece en el dashboard?

---

## Actividad 10 — Cleanup (5 min)

Eliminá desde la consola los dashboards, alarmas y metric filters creados durante el lab.

Después, el profesor ejecuta el workflow con acción `destroy`.

Verificá que no queden EC2s, security groups, instance profiles ni log groups del lab.

---

## Entregables

- URL del workflow ejecutado y outputs de Terraform.
- Evidencia de frontend y backend funcionando.
- Captura de logs frontend y backend.
- Captura del dashboard con métricas.
- Captura de una alarma en `ALARM` durante el incidente.
- Una consulta de Logs Insights y su interpretación.
- Confirmación del cleanup.

---

## Próximo paso: LAB02

En LAB01 configuraste el monitoreo desde la consola para entender cada pieza. En LAB02 vas a escribir un spec de monitoreo y después vas a declarar esos mismos metric filters, dashboard y alarmas con Terraform.

La comparación central será:

```text
LAB01: consola → resultado visible
LAB02: spec → agente/plan → Terraform → resultado repetible
```

---

## Troubleshooting

### El workflow falla antes de Terraform

Revisá secrets, región, branch y permisos de Actions. No agregues credenciales al código.

### No aparece un log group

Esperá el bootstrap de EC2 y generá tráfico. El CloudWatch Agent crea el log group cuando comienza a enviar el archivo configurado.

### El metric filter no encuentra coincidencias

Copiá una línea real del log y probá el patrón en **Test pattern**. No adivines la posición de los campos.

### La alarma queda en `INSUFFICIENT_DATA`

Generá tráfico y esperá el período de evaluación. `notBreaching` evita que la ausencia de datos dispare la alarma.

### No se ve el pico en el dashboard

Ajustá el rango temporal y verificá que la región sea `us-east-1`. Las métricas de logs pueden tardar unos minutos.

### Cleanup

No borres recursos compartidos. Usá el identificador del lab para distinguir lo creado en esta clase.
