# CloudCuyo Migration Lab — Formatec Cloud 2026

Repositorio del curso Arquitectura e Ingenieria Cloud | C2

Profesor: Nicolas Pannucio

## Branch actual

Esta branch contiene el material de:

| Branch | Modulo | Contenido |
|---|---|---|
| `m3-c1-lab` | M3 - Clase 1 | Introduccion a Infrastructure as Code con Terraform sobre AWS |

## Laboratorio incluido

| LAB | Guia | Proyecto Terraform | Foco |
|---|---|---|---|
| LAB01 | `guias/guia-iac-lab01-terraform-s3.md` | `terraform/iac-lab01-s3-basics/` | Provider, recursos, variables, plan, state, apply y destroy usando S3 |

## Como usar esta branch

```bash
git clone https://github.com/nicopannu/curso-cloud-formatec-c2-2026.git
cd curso-cloud-formatec-c2-2026
git checkout m3-c1-lab
```

Para trabajar el laboratorio:

```bash
cd terraform/iac-lab01-s3-basics
terraform init
terraform fmt -check
terraform validate
terraform plan
```

`terraform apply` y `terraform destroy` modifican recursos reales en AWS. Ejecutarlos solo cuando el docente autorice el uso de la cuenta de laboratorio.

## Idea central de la clase

Si la infraestructura se crea a mano, no es repetible. Si no es repetible, no es confiable.

El objetivo no es aprender S3 como servicio principal, sino usar un recurso barato, rapido y facil de limpiar para entender como Terraform convierte una decision de infraestructura en codigo revisable.

---

Proyecto educativo — Formatec Cloud Course 2026
