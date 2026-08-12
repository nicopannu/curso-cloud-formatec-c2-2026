# Formatec Cloud 2026 — M3-C5 Monitoreo proactivo

Repositorio del curso **Arquitectura e Ingeniería Cloud | C2**.

**Profesor:** Nicolás Pannucio
**Módulo:** M3 — Clase 5: monitoreo proactivo
**Branch:** `m3-c5-lab`

## Contexto

Banco Patacon tiene un frontend web y un backend de transferencias. La infraestructura ya está declarada con Terraform. En esta clase se construye, a partir de un spec, un workflow manual de GitHub Actions que ejecuta ese Terraform.

El workflow deja disponible el sistema que vamos a monitorear:

```text
spec → plan del agente → GitHub Actions → Terraform apply
→ frontend + backend → tráfico → logs → métricas → dashboard → alarmas
```

El foco no es desplegar por desplegar. El foco es observar qué ocurre después del deploy y construir evidencia operativa.

## Arquitectura objetivo

```mermaid
flowchart LR
  SPEC[Spec del workflow] --> AGENT[Cursor Plan Mode]
  AGENT --> WF[GitHub Actions]
  WF --> TF[Terraform]
  TF --> FE[EC2 Frontend nginx]
  TF --> BE[EC2 Backend Flask]
  FE --> FLOG[/aws/frontend/access]
  BE --> BLOG[/aws/backend/app]
  FLOG --> CW[CloudWatch Logs]
  BLOG --> CW
  CW --> MF[Metric filters]
  CW --> DASH[Dashboard]
  CW --> ALARM[Alarmas]
```

### Componentes y qué monitoreamos

| Componente | Qué observamos |
|---|---|
| Frontend nginx | Requests, status HTTP, errores 5xx |
| Backend Flask | Transferencias exitosas/erróneas, endpoint, duración |
| EC2 | CPU, red y estado de instancia |
| CloudWatch Logs | Evidencia detallada de cada request y evento |
| Metric filters | Métricas derivadas de líneas de log |
| Dashboard | Volumen, errores y saturación en una vista |
| Alarmas | Condiciones que requieren atención |

## Laboratorios

| # | Guía | Formato | Foco |
|---|---|---|---|
| LAB01 | [`guias/guia-monitoreo-lab01-consola.md`](guias/guia-monitoreo-lab01-consola.md) | En vivo | Spec del workflow, deploy, tráfico y monitoreo por consola |
| LAB02 | [`guias/guia-monitoreo-lab02-terraform.md`](guias/guia-monitoreo-lab02-terraform.md) | Tarea | Monitoreo como código con Terraform |

## Specs

- [`specs/guia-de-specs.md`](specs/guia-de-specs.md): cómo escribir specs útiles para agentes.
- [`specs/lab01-workflow-spec-guia.md`](specs/lab01-workflow-spec-guia.md): guía del spec para construir el workflow en vivo.

El workflow se construye durante LAB01. No se incluye terminado en el repositorio: el objetivo es practicar spec → plan → revisión → implementación.

## Estructura

```text
m3-c5-lab/
├── specs/                        # Guías para escribir los specs
├── terraform/infra/              # Frontend, backend, IAM, SG y CloudWatch Agent
│   └── user-data/                # Bootstrap de las EC2
├── scripts/generar-trafico.sh    # Tráfico normal + errores 500 simulados
└── guias/                        # LAB01 y LAB02
```

## Setup

```bash
git fetch origin m3-c5-lab
git switch m3-c5-lab
```

Codespaces: <https://codespaces.new/nicopannu/curso-cloud-formatec-c2-2026?ref=m3-c5-lab>

## Seguridad y cleanup

- Las credenciales de AWS se cargan como secrets de GitHub Actions; nunca se commitean.
- No commitear `.terraform/`, `terraform.tfstate` ni backups.
- El state remoto usa el bucket compartido entregado para el curso mediante la variable `TF_STATE_BUCKET`.
- Ese bucket es infraestructura compartida y **nunca se elimina** con `terraform destroy` de un lab.
- Cada despliegue usa una key aislada: `m3-c5/<student_identity>/infra.tfstate`.
- El workflow usa `workflow_dispatch`: `apply` y `destroy` son acciones explícitas.
- Al finalizar LAB01, eliminar dashboards, alarmas, metric filters y toda la infraestructura creada.
- No borrar recursos compartidos de otras clases.
