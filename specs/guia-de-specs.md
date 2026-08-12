# Guía de specs — M3-C5

**Objetivo:** aprender a escribir specs que un agente (o un compañero) pueda implementar sin ambigüedad.

Un spec no es el código. Un spec describe **qué** hay que construir, con suficiente detalle para que otro lo implemente sin tener que adivinar.

---

## ¿Por qué specs?

En los labs anteriores recibiste archivos ya escritos (Terraform, Ansible, workflows). En este módulo vas a escribir specs antes de tocar código. Motivos:

1. **Separar diseño de implementación.** Primero pensás qué querés. Después buscás cómo se hace.
2. **Comunicar sin ambigüedad.** Un spec bien escrito se lo das a un agente y te devuelve código que hace exactamente lo que pediste.
3. **Versionar decisiones.** El spec documenta por qué existe cada recurso, no solo cómo se crea.

---

## Anatomía de un spec

Un buen spec tiene siempre estas secciones:

### 1. Objetivo

Una frase que resume qué se va a construir y por qué.

```text
Malo:  "Crear recursos de monitoreo."
Bueno: "Crear métricas, dashboards y alarmas en CloudWatch para
        detectar errores 5xx en el frontend de Banco Patacon antes
        de que los usuarios los reporten."
```

### 2. Contexto

Qué infraestructura o servicios ya existen y no se tocan. Qué sabe el lector.

```text
Ya está desplegado: 2 EC2s (frontend nginx, backend Flask) con
CloudWatch agent enviando logs a /aws/frontend/access y
/aws/backend/app. No modificar esta infraestructura.
```

### 3. Recursos requeridos

Cada recurso se describe con:

- **Qué hace** (una línea)
- **Nombre lógico** (cómo lo vas a referenciar en el spec)
- **De dónde sale** (fuente de datos: log group, métrica nativa, nada)
- **Detalles específicos:** namespace, unidad, umbral, período, patrón de filtro

Ejemplo de un recurso bien especificado:

```text
### Metric filter — Errores del frontend

Qué hace: cuenta requests con status 5xx desde logs de nginx.
Nombre lógico: frontend_5xx
Log group fuente: /aws/frontend/access
Patrón: buscar " 5xx " en el campo de status code del access log
Métrica emitida:
  - namespace: BancoPatacon/Monitoreo
  - nombre: Frontend5xx
  - valor: 1 por coincidencia
  - unidad: Count
```

### 4. Restricciones

Lo que NO hay que hacer, naming conventions, limitaciones de la cuenta.

```text
- No usar SNS ni canales de notificación.
- Todos los recursos llevan prefijo con student_identity.
- Tratamiento de missing data: notBreaching.
- Umbrales definidos como variables, no hardcodeados.
```

---

## Cómo escribir un spec paso a paso

### Paso 1 — Arrancá por la necesidad operativa

No pienses en Terraform. Pensé en la operación:

```text
"Quiero saber si el frontend está devolviendo errores 5xx."
"Quiero ver en un dashboard cuántos errores hubo en la última hora."
"Quiero que alguien se entere si hay más de 5 errores en 10 minutos."
```

### Paso 2 — Traducí cada necesidad a un recurso

| Necesidad | Recurso | Fuente |
|---|---|---|
| Saber si hay 5xx | Metric filter | Log group del frontend |
| Ver en dashboard | Dashboard widget | Métrica del filtro |
| Enterarse a tiempo | Alarm | Métrica + umbral |

### Paso 3 — Especificá cada recurso con precisión

Para un metric filter necesitás: log group, patrón, namespace, nombre de métrica, valor, unidad.

Para un dashboard necesitás: métricas de cada widget, tipo de gráfico, estadística, período, coordenadas.

Para una alarma necesitás: métrica, estadística, umbral, períodos de evaluación, datapoints, tratamiento de missing data.

### Paso 4 — Revisá el spec antes de codificar

Hacete estas preguntas:

- ¿Puede alguien que no vio la clase implementar esto sin preguntarme nada?
- ¿Cada recurso tiene definida su fuente de datos?
- ¿Los nombres son consistentes entre recursos?
- ¿Está claro qué NO hay que hacer?

---

## Spec vs código

| Spec | Código |
|---|---|
| "Crear un metric filter que emita la métrica Frontend5xx" | `resource "aws_cloudwatch_log_metric_filter" "frontend_5xx" { ... }` |
| "namespace: BancoPatacon/Monitoreo" | `namespace = "BancoPatacon/Monitoreo"` |
| "patrón: status code 5xx en logs de nginx" | `pattern = "[ip, user, timestamp, tz, request, status=5*, bytes, referer, agent]"`

El spec es el plano. El código es la construcción. No confundirlos.

---

## Para el agente

Si usás un agente (Claude, Cursor, Copilot) para implementar, pegale el spec completo y decile:

```text
Implementá este spec en Terraform. No agregues recursos que no
estén en el spec. Usá variables para student_identity y umbrales.
Seguí las restricciones al pie de la letra.
```

Un buen spec produce código correcto en la primera iteración. Si el agente falla, el spec está ambiguo — mejorá el spec antes de corregir el código a mano.
