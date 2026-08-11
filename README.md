# Formatec Cloud 2026 — M3-C5 Monitoreo proactivo

Repositorio del curso **Arquitectura e Ingeniería Cloud | C2**.

**Profesor:** Nicolás Pannucio
**Módulo:** M3 — Clase 5: monitoreo proactivo
**Branch:** `m3-c5-lab`

## Secuencia de laboratorios

| # | Guía | Formato | Foco | AWS |
|---|---|---|---|---|
| LAB01 | `guias/guia-monitoreo-lab01-dataset.md` | Individual/grupal | Análisis de incidente, SLI/SLO, diseño de dashboards y alertas | ❌ |
| LAB02 | `guias/guia-monitoreo-lab02-consola.md` | En clase (vivo) | CloudWatch: logs, metric filters, dashboard, alarmas por consola | ✅ |
| LAB03 | `guias/guia-monitoreo-lab03-terraform.md` | Tarea individual | Monitoreo como código con Terraform | ✅ |

## Arquitectura

```
Terraform ──▶ EC2 frontend (nginx) + EC2 backend (Flask)
                    │
          CloudWatch agent ──▶ /aws/frontend/access
                               /aws/backend/app
```

## Specs

`specs/guia-de-specs.md` enseña **cómo escribir specs** para que un agente (o un compañero) implemente sin ambigüedad. El workflow de GitHub Actions y los specs concretos de cada lab se construyen en clase.

## Estructura del repositorio

```
m3-c5-lab/
├── specs/                        # Guía de cómo escribir specs
├── terraform/infra/              # Infraestructura (frontend + backend)
│   └── user-data/                # Scripts de bootstrap
├── scripts/generar-trafico.sh    # Simulador de tráfico para LAB02
├── guias/                        # Guías de los 3 labs
├── datos/                        # Dataset del incidente (LAB01)
├── plantillas/                   # Matriz SLI/SLO/alertas (LAB01)
└── material-docente/             # Guion de clase + slides outline
```

## Setup rápido

```bash
git fetch origin m3-c5-lab
git switch m3-c5-lab
```

Codespaces: <https://codespaces.new/nicopannu/curso-cloud-formatec-c2-2026?ref=m3-c5-lab>

## Seguridad

- AK/SAK cargadas en GitHub Secrets (`AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`)
- No commitear credenciales, `.terraform/`, `terraform.tfstate` ni backups
- Hacer `terraform destroy` al finalizar cada lab
