# Contexto Operativo Para Agentes — Labs HA (M2C2)

Este repositorio contiene los laboratorios del curso **Arquitectura e Ingenieria Cloud | C2 - Formatec Cloud 2026**. Esta branch (`m2-c2-lab`) corresponde al módulo de **Alta Disponibilidad** y es completamente independiente de la branch `m2-c1-lab` (Labs 6R).

El caso de trabajo es **CloudCuyo S.A.**, empresa ficticia de hosting en Mendoza. Los labs HA asumen que el alumno ya conoce el caso pero no requieren haber completado los labs anteriores.

---

## Forma de Trabajo

- Esta branch es autónoma. No tiene dependencia de `m2-c1-lab` ni de `main`.
- Cada lab es también autónomo entre sí. El alumno puede hacer HA-01, HA-02 y HA-03 en secuencia o de forma independiente.
- Los recursos creados por CloudFormation son dinámicos: se crean y eliminan por lab. Los pre-requisitos (VPC, subnets, IAM role SSM) son persistentes y se crean manualmente.
- No hardcodear IDs reales de cuenta AWS en guías para alumnos. Usar siempre variables/placeholders (`$VPC_ID`, `$ALB_DNS`, etc.).
- No exponer credenciales. Usar perfiles AWS configurados localmente.

---

## Perfil AWS del Curso

```bash
aws sts get-caller-identity --profile curso
```

- Profile local: `curso`
- Region: `us-east-1`
- Account ID: `485617552563`

---

## Estructura del Repo (esta branch)

```
cloudformation/
  README.md                        # documentacion de los stacks HA
  ha-lab1-nodes.yaml               # Lab HA-01: 2 EC2 API Flask
  ha-lab2-traffic-gen.yaml         # Labs HA-02 y HA-03: traffic generator

guias/
  guia-ha-01-alb-instancias.md     # ALB + 2 nodos manuales, failover basico
  guia-ha-02-asg-trafico.md        # ASG + Launch Template manual + scaling + traffic gen
  guia-ha-03-healthchecks.md       # EC2 vs ELB health check, shallow vs deep, CloudWatch
```

---

## Pre-Requisitos de Cuenta (persistentes, manuales)

Los alumnos crean estos recursos una sola vez antes de los labs. Quedan en la cuenta:

- **VPC** con CIDR `10.0.0.0/16` e Internet Gateway
- **Public Subnet AZ-A** (`10.0.0.0/24`) + route table → IGW
- **Private Subnet AZ-A** (`10.0.1.0/24`)
- **Public Subnet AZ-B** (`10.0.2.0/24`) + route table → IGW  ← alumno crea
- **Private Subnet AZ-B** (`10.0.3.0/24`)  ← alumno crea
- **IAM Role SSM** con policy `AmazonSSMManagedInstanceCore` + Instance Profile

---

## Recursos Dinámicos por Lab (CloudFormation)

| Stack | Lab | Eliminar cuando |
|---|---|---|
| `cloudcuyo-ha-lab1-nodes` | HA-01 | Al inicio del Lab HA-02 |
| `cloudcuyo-ha-traffic-gen` | HA-02 y HA-03 | Al finalizar el módulo |

---

## Recursos Manuales por Lab (alumno crea en consola)

| Recurso | Lab | Persistencia |
|---|---|---|
| SG del ALB | HA-01 | Se reutiliza en HA-02 y HA-03 |
| ALB | HA-01 | Se reutiliza en HA-02 y HA-03 |
| Target Group | HA-01 | Se reutiliza en HA-02 y HA-03 |
| Launch Template | HA-02 | Se reutiliza en HA-03 |
| ASG | HA-02 | Se modifica en HA-03 |
| Scaling Policy | HA-02 | Se reutiliza en HA-03 |

---

## App Flask en los Nodos

Los stacks CF bootstrapean Amazon Linux 2023 con una API Flask mínima. No requiere DB.

| Endpoint | Descripcion |
|---|---|
| `GET /health` | `{"node": "<instance-id>", "az": "<az>", "status": "ok"}` |
| `GET /api/v1/health` | idem + `"version": "v1"` |
| `GET /api/v1/crash` | Mata el proceso gunicorn en esa instancia (Lab HA-03) |
| `GET /health/deep` | Simula check de dependencia externa (Lab HA-03) |

El campo `node` contiene el `instance-id` de la EC2. Sirve para verificar que el ALB distribuye tráfico entre instancias distintas.

---

## Convenciones

- Naming de recursos CF: `${ProjectName}-<recurso>-${Environment}` (default: `cloudcuyo-<recurso>-ha-lab`)
- Tag obligatorio en todos los recursos CF: `Lab: m2-c2-ha`
- Region del lab: `us-east-1`
- Instance type default: `t3.micro`
