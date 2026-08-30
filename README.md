# CloudCuyo Migration Lab — Formatec Cloud 2026

Repositorio del curso **Arquitectura e Ingeniería Cloud | C2**.

**Profesor:** Nicolás Pannucio

## Organización

Todos los laboratorios viven dentro de `labs/`. Cada lab es autocontenido: incluye su README, guías, infraestructura y scripts. Cuando una práctica requiere automatización, el workflow se construye o se publica en `.github/workflows/` para que GitHub Actions pueda descubrirlo:

```text
labs/
├── m2-c1-lab/
├── m2-c2-lab/
├── m2-c3-lab/
├── m2-c4-lab/
├── m3-c1-lab/
├── m3-c2-lab/
├── m3-c4-lab/
└── m3-c5-lab/
```

Los alumnos trabajan desde `main` y entran a la carpeta indicada por la clase. Ya no es necesario cambiar de branch para encontrar el material de cada lab.

## Labs disponibles

| Carpeta | Tema |
|---|---|
| `labs/m2-c1-lab` | Migración inicial a AWS |
| `labs/m2-c2-lab` | Alta disponibilidad, ALB y Auto Scaling |
| `labs/m2-c3-lab` | Modernización y microservicios |
| `labs/m2-c4-lab` | Contenedores, Docker Swarm y serverless |
| `labs/m3-c1-lab` | Infrastructure as Code con Terraform |
| `labs/m3-c2-lab` | Gestión de configuración con Ansible |
| `labs/m3-c4-lab` | Pipelines CI/CD con GitHub Actions |
| `labs/m3-c5-lab` | Monitoreo proactivo con CloudWatch |

## Recursos adicionales

Estos recursos son independientes de los labs y se publican para reutilizarlos desde `main`:

| Recurso | Propósito |
|---|---|
| [`recursos/aws-resource-alerts/`](recursos/aws-resource-alerts/) | Stack CloudFormation que revisa recursos AWS diariamente y avisa por email |

El stack de avisos requiere únicamente una dirección de email como parámetro. La suscripción SNS debe confirmarse desde el correo recibido. No elimina recursos y debe eliminarse cuando ya no se necesite.

## Codespaces

1. Abrí el repositorio.
2. Presioná **Code → Codespaces → Create codespace on main**.
3. Verificá la ubicación:

```bash
git branch --show-current
```

Cada guía indica el directorio del lab y sus comandos. Codespaces prepara las herramientas, pero no reemplaza la cuenta AWS, los permisos ni el cleanup.

## Reglas generales

- No commitear credenciales, tokens, state, planes ni archivos `.env`.
- Leer el README y la guía dentro de `labs/<lab>/` antes de ejecutar comandos.
- Usar el Environment y las variables indicadas por cada lab.
- Ejecutar `destroy` al finalizar cuando la práctica cree recursos AWS.
- No eliminar buckets de state ni recursos compartidos.
- Los workflows de cada lab se ejecutan según su propio `workflow_dispatch` y sus condiciones documentadas.

## M3-C5

El nuevo flujo está en [`labs/m3-c5-lab/`](labs/m3-c5-lab/):

```text
spec → IDE agéntico → workflow construido en clase → Terraform
→ frontend + backend → tráfico → CloudWatch
→ logs → metric filters → dashboard → alarmas
```

El workflow de M3-C5 se construye durante LAB01 a partir de un spec. La infraestructura, las guías y el script de tráfico viven en `labs/m3-c5-lab/`; cuando el workflow exista, GitHub Actions lo descubre desde `.github/workflows/` en `main`.

## Entornos anteriores

Las branches históricas por módulo se conservan como referencia y rollback. El material canónico para los alumnos pasa a ser el que está debajo de `labs/` en `main`.
