# M3-C5 — Guion de clase: monitoreo proactivo

**Curso:** Arquitectura e Ingeniería Cloud | C2 — Formatec 2026
**Profesor:** Nicolás Pannucio
**Duración:** 90 minutos
**Caso:** Banco Patacon después del pipeline CI/CD

## Resultado esperado

Al terminar, los estudiantes deben poder pasar de “mirar gráficos” a definir:

```text
pregunta operativa
→ señal
→ indicador
→ objetivo
→ alerta
→ acción
```

Deben distinguir evidencia, hipótesis y causa raíz.

## Preparación docente

- Abrir el workflow M3-C4 y un run conocido para recordar `deploy → smoke test`.
- Tener visible `datos/incidente-banco-patacon.csv`.
- Preparar una hoja o pizarra con tres columnas: métricas, logs, trazas.
- Opcional: abrir CloudWatch con una EC2 de demo ya creada y sin datos sensibles.
- No depender de crear infraestructura durante la clase.

## Agenda de 90 minutos

| Bloque | Duración | Propósito |
|---|---:|---|
| Apertura: después del pipeline verde | 10 min | Instalar el problema operativo |
| Conceptos: señales y objetivos | 20 min | Métricas, logs, trazas, SLI y SLO |
| Demo docente | 15 min | Leer un incidente y un dashboard como sistema de decisión |
| LAB01 | 35 min | Diseñar dashboard, alertas y runbook |
| Puesta en común y cierre | 10 min | Comparar decisiones y corregir anti-patrones |

## 1. Apertura — 10 minutos

Mostrar el final de **M3-C4 LAB01**:

```text
Terraform apply
→ Ansible
→ HTTP 200
→ workflow verde
```

Plantear:

> El pipeline terminó a las 09:15. A las 09:30 los usuarios informan errores. ¿El pipeline estaba equivocado?

Respuesta a construir:

- El smoke test fue evidencia válida para ese instante.
- No garantizaba salud futura ni corrección funcional completa.
- La operación necesita señales continuas y contexto de cambios.

Frase útil:

> CI/CD responde “¿podemos entregar este cambio?”. Monitoreo responde “¿cómo se está comportando el servicio ahora?”.

Checkpoint oral:

- ¿Qué dato conservarían del pipeline para correlacionarlo con una degradación?
- ¿Un HTTP 200 aislado representa disponibilidad?

## 2. Conceptos — 20 minutos

### Monitoreo y observabilidad

- Monitoreo: preguntas conocidas, señales y umbrales preparados.
- Observabilidad: capacidad de investigar estados internos a partir de salidas, incluso ante preguntas no previstas.
- No presentarlos como productos: son capacidades operativas.

### Métricas, logs y trazas

| Señal | Responde bien | Limitación |
|---|---|---|
| Métrica | cuánto, con qué frecuencia, desde cuándo | pierde detalle individual |
| Log | qué evento ocurrió y con qué campos | volumen, búsqueda y contexto |
| Traza | dónde pasó tiempo o falló una solicitud distribuida | instrumentación y costo |

Ejemplo oral:

- Métrica: 19,4% de respuestas fueron 5xx.
- Log: `POST /transferencias` devolvió 500 por timeout.
- Traza: la espera se concentró en el servicio de saldos.

### Health check y corrección

- Proceso vivo no significa operación funcional correcta.
- Puerto abierto no significa transacción exitosa.
- Un check profundo puede ejercer dependencias, pero también agregar carga y ruido.

### SLI, SLO y SLA

- SLI: medición concreta.
- SLO: objetivo interno sobre una ventana.
- SLA: compromiso externo con consecuencias acordadas.

Ejemplos:

```text
SLI de 5xx = respuestas 5xx / total de respuestas
SLI de latencia = intervalos cuyo p95 cumple el umbral / total de intervalos
```

Aclarar:

- la tasa 5xx no equivale a disponibilidad externa ni éxito de negocio;
- el dataset no contiene probes externos;
- no se deben promediar p95 para obtener el p95 global;
- cada SLO necesita alcance, población y ventana.

## 3. Demo docente — 15 minutos

Abrir el CSV y recorrerlo sin comenzar por la columna `change_event`.

Orden recomendado:

1. Solicitudes y 5xx: calcular la tasa, no mirar sólo el número absoluto.
2. Latencia p95: detectar degradación antes del pico.
3. CPU y memoria: observar correlación sin declarar causalidad.
4. Recién entonces mostrar `change_event` y ubicar deploy/rollback.

Valores de referencia para conducir la demo:

- La degradación comienza a las 09:20.
- El peor intervalo es 09:30: 37 errores sobre 191 solicitudes, aproximadamente 19,4%.
- La latencia p95 llega a 1640 ms.
- CPU y memoria también aumentan.
- Existe correlación temporal con el deploy de 09:15, pero el CSV no prueba la causa raíz.
- La recuperación comienza después del rollback y vuelve cerca de baseline a las 09:50.

Pregunta clave:

> Si sólo tuviéramos CPU, ¿podríamos saber si los usuarios estaban recibiendo errores?

Respuesta: no. CPU es una señal de recurso; la tasa de errores y la latencia representan mejor el impacto.

### Demo CloudWatch opcional

Mostrar, sin crear recursos en vivo:

- `AWS/EC2 → CPUUtilization`;
- `AWS/EC2 → StatusCheckFailed`;
- período, estadística, dimensión y missing data;
- estados disponibles e historial de alarma, sin prometer que aparecerán los tres durante la clase;
- diferencia entre dashboard, alarma técnica y alerta operativa.

No afirmar que memoria o logs de Nginx aparecen automáticamente. Requieren CloudWatch Agent o instrumentación equivalente y permisos de escritura.

## 4. LAB01 — 35 minutos

### Organización

- 3 min: preparar la copia de entrega.
- 7 min: leer el dataset y calcular tres tasas.
- 8 min: definir dos SLI/SLO y una señal faltante.
- 7 min: diseñar tres paneles.
- 7 min: definir dos alertas.
- 3 min: completar runbook y conclusión.

### Checkpoints docentes

Checkpoint 1 — datos:

- El equipo usa tasa de error, no sólo conteo.
- La tasa de 09:30 es aproximadamente 19,37%.
- Separa impacto de saturación y correlación de causalidad.

Checkpoint 2 — SLI/SLO:

- Hay fórmula, alcance, fuente, ventana y limitación.
- Nadie promedia p95.
- La disponibilidad externa queda marcada como señal faltante.

Checkpoint 3 — dashboard:

- Hay exactamente tres paneles.
- Cada panel responde una pregunta.
- Deploy y rollback aparecen como eventos.

Checkpoint 4 — alertas:

- Hay una alerta de impacto y una técnica.
- Cada una define evaluación, missing data, responsable, acción y recuperación.

### Intervenciones útiles

Si un equipo alerta sólo por CPU:

> ¿Qué harían si CPU llega a 95% y la latencia sigue normal?

Si un equipo define “disponibilidad 100%”:

> ¿Qué costo y sensibilidad tendría ese objetivo? ¿Qué ventana usan?

Si un equipo afirma que el deploy causó el incidente:

> ¿Qué evidencia adicional pedirían para pasar de correlación a causalidad?

## 5. Puesta en común y cierre — 10 minutos

Comparar dos diseños de alerta:

```text
A: CPU > 80% una vez
B: 5xx > 5% durante 10 minutos y volumen suficiente
```

Discutir:

- cuál está más cerca del impacto;
- cuál tiene contexto suficiente;
- qué equipo puede responder;
- qué falso positivo podría ocurrir;
- por qué B necesita metric math y tratamiento de períodos sin tráfico si se implementa en CloudWatch.

Cierre oral:

> Un dashboard ayuda a investigar. Una alerta pide una acción. Un SLO define cuánto deterioro aceptamos. Ninguno reemplaza conocer la arquitectura.

Preguntas finales:

1. ¿Qué señal muestra primero la degradación?
2. ¿Qué panel quitarían si no habilita ninguna decisión?
3. ¿Qué diferencia hay entre síntoma y causa?
4. ¿Qué requiere agente o instrumentación adicional en EC2?
5. ¿Qué dato del pipeline debe aparecer en el dashboard?

## Scope cuts

No intentar en una misma clase:

- desplegar Prometheus y Grafana;
- instalar CloudWatch Agent en todos los equipos;
- instrumentar trazas distribuidas completas;
- configurar SNS, escalamiento automático e incident management;
- implementar un SLO mensual real.

La clase debe cerrar con decisiones observables y defendibles. La implementación avanzada puede continuar en una extensión separada.
