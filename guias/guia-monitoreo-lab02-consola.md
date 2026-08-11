# M3-C5 LAB02 — Monitoreo en vivo: logs, métricas y alarmas

**Módulo:** M3-C5 — Monitoreo proactivo
**Duración estimada:** ~50 minutos (guiado en clase)
**Branch:** `m3-c5-lab`
**Dependencia:** LAB01 completado

---

## Contexto

En LAB01 analizaste un incidente de Banco Patacon a partir de un dataset: calculaste tasas de error, definiste SLI/SLO, diseñaste dashboards y propusiste alertas. Todo sobre papel.

Ahora vas a hacer eso mismo sobre un sistema real. Banco Patacon tiene su frontend y backend corriendo en EC2, con logs fluyendo a CloudWatch. Tu tarea es recorrer el camino inverso al incidente: ver los logs, crear métricas, armar un dashboard, configurar alarmas y simular un mini-incidente para verlas dispararse.

Todo se hace desde la consola de AWS. Sin Terraform, sin código. El objetivo es entender qué hace cada pieza antes de declararla como código en el próximo lab.

---

## Arquitectura

El profesor ya desplegó la infraestructura:

```
EC2 frontend (nginx)                    EC2 backend (Flask)
  │                                        │
  │  /var/log/nginx/access.log             │  stdout JSON logs
  ▼                                        ▼
CloudWatch agent ─────────────▶  CloudWatch agent
  │                                        │
  ▼                                        ▼
/aws/frontend/access              /aws/backend/app
  │                                        │
  └────────────────┬───────────────────────┘
                   ▼
           CloudWatch Logs
                   │
           ┌───────┼──────────┐
           ▼       ▼          ▼
     Metric Filters  Dashboard  Alarmas
```

---

## Objetivos

- Explorar logs reales en CloudWatch.
- Crear metric filters para extraer métricas desde logs.
- Construir un dashboard que responda preguntas operativas.
- Configurar alarmas que cambien de estado ante condiciones reales.
- Simular tráfico que genere errores y observar la reacción de las alarmas.
- Investigar un pico de errores usando Logs Insights.

---

## Alcance

En este lab hacés todo desde la consola AWS. No escribís Terraform ni YAML. No configurás SNS ni canales de notificación (las alarmas cambian de estado en la consola, sin notificar a nadie). No modificás la infraestructura.

---

## Prerrequisitos

- Branch `m3-c5-lab`.
- Acceso a la consola AWS con permisos de CloudWatch.
- URLs del frontend y backend (las comparte el profesor).
- Terminal con `curl` para generar tráfico.

---

## Actividad 1 — Verificar los servicios (3 min)

El profesor te da dos URLs. Verificá que ambas respondan:

```bash
curl <FRONTEND_URL>
curl <BACKEND_URL>/health
```

El frontend devuelve la página de estado de Banco Patacon. El backend devuelve `{"status":"ok"}`.

---

## Actividad 2 — Explorar los logs (5 min)

Abrí la consola AWS y navegá a **CloudWatch → Log groups**.

Vas a encontrar dos log groups:

| Log group | Contenido | Formato |
|---|---|---|
| `/aws/frontend/access` | Logs de acceso de nginx | Cada línea es un request HTTP |
| `/aws/backend/app` | Logs de la API Flask | Cada línea es un objeto JSON |

Abrí cada uno y explorá algunas líneas. Identificá:

- En el frontend: el campo de status code (200, 404, etc.).
- En el backend: campos `status`, `endpoint`, `duration_ms`.

---

## Actividad 3 — Generar tráfico (3 min)

Para que los logs tengan datos recientes, generá tráfico con el script incluido en el repositorio:

```bash
chmod +x scripts/generar-trafico.sh
./scripts/generar-trafico.sh <FRONTEND_URL> <BACKEND_URL> 120
```

Esto va a generar requests normales y picos de error durante 2 minutos. Mientras corre, volvé a CloudWatch y actualizá los log groups para ver nuevas líneas entrando.

---

## Actividad 4 — Crear metric filters (8 min)

Un metric filter extrae una métrica numérica desde los logs. Cada vez que una línea coincide con un patrón, la métrica se incrementa.

### Filter 1 — Errores 5xx del frontend

1. CloudWatch → Log groups → `/aws/frontend/access` → pestaña **Metric filters** → **Create metric filter**.
2. Patrón de filtro: `[ip, user, timestamp, request, status, ...]` — pero para simplificar, usá un patrón simple. Probá con el patrón que detecte status codes en el rango 500-599. Los logs de nginx tienen el status code como cuarto campo entre espacios. Un patrón que funciona:

   ```
    [,,, status=5*,...]
   ```

   O si preferís un patrón más directo, usá `" 500 "` como prueba inicial. Después generalizá.

   Si el formato del log es el estándar de nginx, el status code aparece después de la URL. Probá filtrar con `Logs Insights` primero para ver el formato exacto: seleccioná el log group y ejecutá:

   ```
   fields @timestamp, @message | limit 20
   ```

3. Una vez que el patrón matchea correctamente (probalo con **Test pattern**), avanzá.
4. **Metric details:**
   - Filter name: `Frontend5xx`
   - Metric namespace: `BancoPatacon/Monitoreo`
   - Metric name: `Frontend5xx`
   - Metric value: `1`
   - Unit: `Count`

### Filter 2 — Errores del backend

Repetí el proceso para `/aws/backend/app`. Los logs del backend son JSON. Buscá líneas que contengan `"status":"error"`.

- Filter name: `BackendErrores`
- Metric namespace: `BancoPatacon/Monitoreo`
- Metric name: `BackendErrores`
- Metric value: `1`
- Unit: `Count`

### Checkpoint

- Dos metric filters creados.
- Namespace `BancoPatacon/Monitoreo` visible en **CloudWatch → Metrics → Custom namespaces**.

---

## Actividad 5 — Construir un dashboard (8 min)

CloudWatch → **Dashboards → Create dashboard**. Nombre: `BancoPatacon-<tu-identidad>`.

Agregá 4 widgets. Para cada uno, elegí el tipo de gráfico que mejor represente la métrica:

| Widget | Métrica | Estadística | Período | Tipo |
|---|---|---|---|---|
| Requests frontend | `AWS/EC2 → NetworkIn` (filtrar por instancia frontend) | Sum | 5 min | Línea |
| Errores 5xx frontend | `BancoPatacon/Monitoreo → Frontend5xx` | Sum | 5 min | Barra |
| Errores backend | `BancoPatacon/Monitoreo → BackendErrores` | Sum | 5 min | Barra |
| CPU | `AWS/EC2 → CPUUtilization` (ambas instancias) | Average | 5 min | Línea |

Ajustá el rango de tiempo a **últimas 3 horas**. Guardá el dashboard.

---

## Actividad 6 — Configurar alarmas (6 min)

CloudWatch → **Alarms → Create alarm**.

### Alarma 1 — Errores del frontend

- **Métrica:** `BancoPatacon/Monitoreo → Frontend5xx`, estadística `Sum`
- **Período:** 5 minutos
- **Condición:** `Static`, `Greater/Equal`, umbral `5`
- **Datapoints to alarm:** 2 de 2
- **Missing data treatment:** `Treat missing data as not breaching`
- **Nombre:** `Frontend5xxAlarm`
- Sin acciones SNS.

### Alarma 2 — Errores del backend

- **Métrica:** `BancoPatacon/Monitoreo → BackendErrores`, estadística `Sum`
- **Período:** 5 minutos
- **Condición:** `Static`, `Greater/Equal`, umbral `1`
- **Datapoints to alarm:** 1 de 1
- **Missing data treatment:** `Treat missing data as not breaching`
- **Nombre:** `BackendErroresAlarm`

---

## Actividad 7 — Simular un incidente (10 min)

Ejecutá el script de tráfico con duración más larga para tener varios períodos de 5 minutos con datos:

```bash
./scripts/generar-trafico.sh <FRONTEND_URL> <BACKEND_URL> 600
```

El script alterna tráfico normal con picos de error (requests a páginas inexistentes en el frontend, transferencias que fallan en el backend).

Mientras corre, observá en tiempo real:

1. **Dashboard:** los widgets de errores deberían mostrar barras más altas durante los picos.
2. **Alarmas:** después de 10 minutos (2 períodos de evaluación), la alarma del frontend debería pasar a `ALARM`. La del backend puede disparar antes porque tiene umbral más bajo.
3. **Logs Insights:** ejecutá consultas para investigar los picos:

   ```
   fields @timestamp, @message
   | filter @message like /404/
   | sort @timestamp desc
   | limit 20
   ```

---

## Actividad 8 — Interpretar (5 min)

Respondé en tu entregable:

1. ¿Cuánto tardó la alarma del frontend en pasar a `ALARM` desde que empezaron los errores? ¿Por qué?
2. ¿Qué diferencia observás entre una alarma con `Treat missing data as not breaching` y una sin ese setting?
3. Si tuvieras que agregar un canal de notificación, ¿a quién le llegaría y por qué medio?
4. ¿Qué información te dan los logs que el dashboard no muestra?

---

## Troubleshooting

### No veo los log groups

El CloudWatch agent puede tardar unos minutos en crear los log groups después del deploy. Si no aparecen, esperá 2-3 minutos y refrescá.

### El patrón del metric filter no matchea

Abrí algunas líneas del log group y copiá una línea real. Pegala en **Test pattern**. Si el formato no es el esperado, ajustá el patrón. Lo importante es que matchee correctamente las líneas con error.

### La alarma queda en INSUFFICIENT_DATA

Si no hay tráfico, la métrica no recibe datos. Esperá a que el script genere tráfico. Con `Treat missing data as not breaching`, la alarma trata la falta de datos como "OK" (no hay problema).

### El dashboard no muestra datos

Revisá que el rango de tiempo incluya los minutos en que corriste el script. Si usaste "últimas 3 horas" debería alcanzar. También verificá que el namespace `BancoPatacon/Monitoreo` exista en Custom metrics.

---

## Cleanup

Eliminá desde la consola solo lo que creaste durante el lab:

1. **Dashboard:** CloudWatch → Dashboards → `BancoPatacon-<tu-identidad>` → Delete
2. **Alarmas:** CloudWatch → Alarms → seleccionar las dos → Actions → Delete
3. **Metric filters:** CloudWatch → Log groups → seleccionar cada log group → Metric filters → seleccionar → Delete

La infraestructura (EC2s) se destruye con `terraform destroy` al finalizar la clase. No elimines recursos compartidos.

---

## Entregables

- Captura del dashboard con las 4 métricas durante un pico de errores.
- Captura de una alarma en estado `ALARM`.
- Resultado de una consulta de Logs Insights durante el incidente.
- Respuestas de la Actividad 8.
