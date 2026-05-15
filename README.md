# CloudCuyo Migration Lab — Formatec Cloud 2026

Proyecto educativo para el módulo de migración cloud. Simula una empresa ficticia (**CloudCuyo S.A.**) con infraestructura on-premise legacy y una migración progresiva a AWS aplicando el **framework 6R**.

## Branches

Cada lab tiene su propia branch. Clonar o cambiar a la branch correspondiente antes de empezar:

| Branch | Contenido |
|---|---|
| `main` | Documentación general, estructura del repo |
| `m2-c1-lab` | Módulo 2 - Clase 1: REHOST + REPLATFORM (Guia 1 y Guia 2) |

```bash
git clone https://github.com/nicopannu/curso-cloud-formatec-c2-2026.git
cd curso-cloud-formatec-c2-2026

# Cambiar a la branch del lab
git checkout m2-c1-lab
```

---

## Estructura del repositorio

```
curso-cloud-formatec-c2-2026/
│
├── docs/                          # Documentación de relevamiento
│   ├── 01-contexto.md             # Contexto de negocio de CloudCuyo
│   ├── 02-inventario-onprem.md    # Inventario técnico on-premise
│   ├── 03-matriz-6r.md            # Estrategia de migración (matriz 6R)
│   └── 07-arquitectura-completa.md # Arquitectura completa y APIs
│
├── guias/                         # Guias de laboratorio paso a paso
│   ├── guia-01-rehost-ec2.md      # Guia 1: Importar OVAs a EC2 (REHOST)
│   └── guia-02-frontend-s3-cloudfront.md  # Guia 2: Frontend a S3 + CloudFront (REPLATFORM)
│
├── vagrant/                       # Entorno local con Vagrant + VirtualBox
│   ├── Vagrantfile                # Configuración de las 5 VMs
│   ├── instrucciones-levantar-vms.md  # Como levantar VMs y exportar OVAs
│   └── EC2-PREPARATION-GUIDE.md  # Detalle de preparación de VMs para EC2
│
├── app/
│   ├── frontend/                  # Sitio web estatico + portal de clientes
│   └── api/                       # Flask API (interna + pública v1)
│
├── database/
│   ├── schema.sql                 # Esquema PostgreSQL con pgcrypto
│   └── seed.sql                   # Datos de prueba (6 clientes)
│
├── scripts/
│   ├── local/                     # Scripts de provisión para Vagrant
│   └── aws/                       # Scripts para operaciones en AWS
│
├── cloudformation/
│   └── nat-instance.yaml          # Template NAT Instance con SSM (Guia 1)
│
└── infra/terraform/               # Placeholder para IaC con Terraform
```

---

## La empresa: CloudCuyo S.A.

Proveedor de hosting y servicios cloud de Mendoza, en operación desde 2001. La empresa corre toda su infraestructura on-premise en un datacenter propio cuyo contrato vence próximamente.

**Arquitectura on-premise actual:**

```
                    [Usuario Web / API Pública]
                              |
                              v
                    ┌─────────────────────┐
                    │   Load Balancer     │
                    │   NGINX (lb01)      │
                    │   192.168.56.10     │
                    └──────────┬──────────┘
                               |
                ┏━━━━━━━━━━━━━━┻━━━━━━━━━━━━━━┓
                ▼                              ▼
        ┌──────────────┐              ┌──────────────────┐
        │  Frontend    │              │  API Backend     │
        │  NGINX       │              │  Flask/Gunicorn  │
        │  frontend01  │◄─────────────┤  api01           │
        │  frontend02  │              │  192.168.56.30   │
        │  .20 / .21   │              └────────┬─────────┘
        └──────────────┘                       │
                                               ▼
                                       ┌──────────────────┐
                                       │  PostgreSQL 14   │
                                       │  + pgcrypto      │
                                       │  db01            │
                                       │  192.168.56.40   │
                                       └──────────────────┘
```

| VM | Rol | IP | Stack |
|---|---|---|---|
| lb01 | Load Balancer | 192.168.56.10 | NGINX |
| frontend01 | Web Server | 192.168.56.20 | NGINX |
| frontend02 | Web Server (HA) | 192.168.56.21 | NGINX |
| api01 | API Backend | 192.168.56.30 | Flask + Gunicorn |
| db01 | Base de datos | 192.168.56.40 | PostgreSQL 14 + pgcrypto |

---

## Estrategia de migración (6R)

| Componente | Estrategia | Destino AWS | Fase |
|---|---|---|---|
| Base de datos | REHOST | EC2 + PostgreSQL (bloqueador: pgcrypto) | 1 |
| Load Balancer | REPLACE | Application Load Balancer | 1 |
| Frontend estático | REPLATFORM | S3 + CloudFront | 2 |
| API Backend | REFACTOR | Lambda + API Gateway o ECS | 3 |
| DB (post re-encriptación) | REPLATFORM | RDS PostgreSQL + KMS | 3 |
| Páginas legacy 2009 | RETIRE | N/A | 4 |
| Funciones con dependencias desconocidas | RETAIN | Monitorear | 4 |

Ver análisis completo en [`docs/03-matriz-6r.md`](docs/03-matriz-6r.md).

---

## Laboratorios

### Guia 1: REHOST — Importar OVAs a EC2
[`guias/guia-01-rehost-ec2.md`](guias/guia-01-rehost-ec2.md)

Migración "lift and shift" de las VMs a AWS EC2. Se usan OVAs ya exportados y preparados (disponibles en S3 público del curso), se importan como AMIs y se despliegan en una VPC con subnets pública y privada. Se usa NAT Instance (CloudFormation) para salida a internet y administración via SSM Session Manager.

- Duracion: 3-4 horas
- Estrategia: REHOST + REPLACE
- OVAs en: `s3://curso-cloud-c2-2026-ovas/`

### Guia 2: REPLATFORM Frontend — S3 + CloudFront
[`guias/guia-02-frontend-s3-cloudfront.md`](guias/guia-02-frontend-s3-cloudfront.md)

Migración del frontend estático de EC2 a S3 + CloudFront. Se configura CloudFront con dos orígenes: S3 para contenido estático y ALB/EC2 como proxy para las APIs. Reducción de costos ~94% ($15 → $0.92/mes).

- Duracion: 2-3 horas
- Estrategia: REPLATFORM

---

## Entorno local con Vagrant

Si querés explorar la arquitectura on-premise antes de migrarla, o regenerar los OVAs desde cero, ver [`vagrant/instrucciones-levantar-vms.md`](vagrant/instrucciones-levantar-vms.md).

```bash
cd vagrant/
vagrant up
```

> Los OVAs del curso ya están disponibles en S3. Levantar las VMs localmente es **opcional**.

---

## Documentación de relevamiento

Los documentos en `docs/` representan el trabajo de relevamiento previo a la migración:

| Documento | Contenido |
|---|---|
| [`01-contexto.md`](docs/01-contexto.md) | Contexto de negocio, historia y problemas actuales |
| [`02-inventario-onprem.md`](docs/02-inventario-onprem.md) | Inventario técnico de la infraestructura on-premise |
| [`03-matriz-6r.md`](docs/03-matriz-6r.md) | Estrategia de migración con justificaciones por componente |
| [`07-arquitectura-completa.md`](docs/07-arquitectura-completa.md) | Arquitectura técnica, flujos de datos y especificación de APIs |

---

## OVAs del curso

Las VMs están exportadas como OVAs con SSM Agent, cloud-init y drivers EC2 preconfigurados. Disponibles en:

```
s3://curso-cloud-c2-2026-ovas/
├── cloudcuyo-db01.ova
├── cloudcuyo-api01.ova
├── cloudcuyo-frontend01.ova
├── cloudcuyo-frontend02.ova
└── cloudcuyo-lb01.ova
```

---

Proyecto educativo — Formatec Cloud Course 2026
