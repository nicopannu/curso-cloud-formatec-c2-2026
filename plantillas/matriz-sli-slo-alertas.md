# Matriz de monitoreo — Banco Patacon

**Integrante o equipo:**
**Fecha:**
**Branch:** `m3-c5-lab`

## 1. Preguntas y señales

| Pregunta operativa | Señal | Tipo: métrica, log, traza o evento | Fuente posible | Decisión que habilita |
|---|---|---|---|---|
| ¿Los usuarios reciben errores o latencia elevada? |  |  |  |  |
| ¿El workload muestra saturación? |  |  |  |  |
| ¿Qué cambio ocurrió antes de la degradación? |  |  |  |  |

## 2. SLI y SLO

| SLI: fórmula exacta | Servicio/ambiente y población | SLO y ventana | Fuente | Exclusiones/datos faltantes | Limitación |
|---|---|---|---|---|---|
| Tasa de 5xx |  |  |  |  |  |
| Cumplimiento de p95 por intervalo |  |  |  |  |  |

Señal ausente que agregarías para medir disponibilidad externa o éxito funcional:

```text

```

## 3. Dashboard propuesto

| Orden | Panel | Visualización/unidad | Período/estadística | Pregunta que responde | Segmentación |
|---:|---|---|---|---|---|
| 1 |  |  |  |  |  |
| 2 |  |  |  |  |  |
| 3 |  |  |  |  |  |

Dibujá el dashboard debajo o adjuntá un wireframe. Marcá los eventos de deploy y rollback.

## 4. Alertas accionables

| Alerta | Señal y condición | Ventana/evaluación | Severidad | Acción y responsable | Posible falso positivo | Condición de recuperación |
|---|---|---|---|---|---|---|
| Impacto al usuario |  |  |  |  |  |  |
| Riesgo técnico |  |  |  |  |  |  |

Para cada alerta confirmá:

- ¿Quién puede actuar cuando se dispara?
- ¿Qué evidencia debe revisar primero?
- ¿Cómo se tratarán intervalos sin tráfico o sin datos?

## 5. Análisis del incidente

**Último intervalo estable:**
**Primer intervalo degradado:**
**Pico:**
**Primer intervalo cercano al baseline después de la mitigación:**
**Correlación con cambios:**
**Hipótesis principal:**
**Datos faltantes para confirmarla:**

## 6. Runbook mínimo — 5 pasos

1. Confirmar la señal y la calidad de los datos:
2. Acotar usuarios, endpoints y ambientes afectados:
3. Correlacionar cambios y revisar evidencia detallada:
4. Mitigar o revertir y verificar recuperación:
5. Preservar evidencia y registrar acciones posteriores:

## 7. Decisión final

Explicá en no más de 120 palabras qué alerta implementarías primero, qué señal todavía falta y por qué la telemetría disponible no demuestra por sí sola una causa raíz.
