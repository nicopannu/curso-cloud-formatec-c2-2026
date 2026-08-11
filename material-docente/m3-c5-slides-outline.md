# M3-C5 — Outline de slides: monitoreo proactivo

**Cantidad:** 15 slides
**Duración objetivo:** 35–40 minutos de exposición y demo, más 35 minutos de lab

## Slide 1 — Monitoreo proactivo

- Subtítulo: del pipeline verde a la operación confiable.
- Pregunta: ¿quién detecta el problema primero, el equipo o el usuario?
- Visual: pipeline que termina en servicio y continúa hacia señales.

## Slide 2 — El pipeline terminó, el sistema sigue

- `deploy → verify` demuestra un punto en el tiempo.
- Después aparecen carga, fallas de dependencia, saturación y drift.
- Takeaway: entregar y operar son capacidades conectadas, no equivalentes.

## Slide 3 — El caso Banco Patacon

- Deploy 09:15.
- Las señales comienzan a degradarse después.
- Pico de errores y latencia 09:30.
- Pregunta: ¿qué se puede afirmar y qué evidencia todavía falta?

## Slide 4 — Monitoreo vs observabilidad

- Monitoreo: preguntas conocidas y señales preparadas.
- Observabilidad: investigar estados no anticipados.
- Evitar “comprar observabilidad” como sinónimo de instalar una herramienta.

## Slide 5 — Tres tipos de evidencia

- Métricas: tendencia y agregación.
- Logs: eventos y contexto.
- Trazas: recorrido y latencia distribuida.
- Ejemplo único de una transferencia fallida visto desde las tres señales.

## Slide 6 — Health check no es corrección funcional

- Proceso vivo.
- Puerto abierto.
- HTTP 200.
- Operación de negocio exitosa.
- Takeaway: cada check cubre una profundidad distinta.

## Slide 7 — Señales orientadas al usuario

- Tráfico.
- Errores.
- Latencia.
- Saturación.
- Distinguir síntomas de recursos internos.

## Slide 8 — De señal a SLI

- Fórmula, población, fuente, unidad y ventana.
- Tasa de 5xx no equivale a disponibilidad externa.
- p95 por intervalo no debe promediarse para producir otro p95.
- Las señales faltantes se instrumentan; no se inventan.

## Slide 9 — SLI, SLO y SLA

- SLI mide.
- SLO fija el objetivo interno.
- SLA formaliza un compromiso externo.
- La ventana cambia la interpretación.

## Slide 10 — Alarma no es alerta operativa

Una alarma evalúa:

- señal y umbral;
- ventana y datapoints;
- datos faltantes;
- condición de recuperación.

Una alerta agrega:

- canal y routing;
- severidad;
- responsable;
- acción y runbook.

## Slide 11 — Estados y ruido

- `OK`, `ALARM`, `INSUFFICIENT_DATA`.
- Un punto aislado vs varios períodos.
- Falsos positivos y fatiga de alertas.
- Takeaway: si nadie sabe qué hacer, no es una alerta útil.

## Slide 12 — CloudWatch como implementación AWS

- Namespaces, métricas, dimensiones y estadísticas.
- EC2 entrega CPU y status checks de forma nativa.
- Memoria y logs de Nginx requieren agente/instrumentación.
- Alarmas técnicas sin canal no notifican ni asignan responsable.
- Tasa 5xx puede requerir métricas de aplicación/ALB y metric math.

## Slide 13 — Dashboard de decisión

Tres paneles:

1. tasa 5xx + volumen;
2. latencia p95;
3. CPU + memoria.

Anotar deploy y rollback. Cada panel responde una pregunta; ninguno demuestra causa raíz por sí solo.

## Slide 14 — LAB01: investigar y diseñar

- Calcular tres tasas 5xx.
- Definir dos SLI/SLO.
- Diseñar tres paneles.
- Proponer dos alertas.
- Escribir runbook de cinco pasos.
- Regla: no confundir correlación con causa raíz.

## Slide 15 — Cierre

```text
pregunta
→ señal
→ indicador
→ objetivo
→ alerta
→ acción
```

Frase final:

> Lo que no se mide se descubre tarde; lo que se alerta sin contexto se convierte en ruido.

Puente: la observabilidad también produce evidencia para seguridad, capacidad y costo.
