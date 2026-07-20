# Formatec Cloud 2026 — M3-C2 Gestión de configuración con Ansible

Repositorio del curso **Arquitectura e Ingeniería Cloud | C2**.

Profesor: Nicolas Pannucio

Branch: `m3-c2-lab`

## Escenario

CloudCuyo ya puede crear infraestructura repetible con Terraform. El nuevo problema aparece después del aprovisionamiento: instalar paquetes, crear usuarios, distribuir archivos y mantener dos servidores con la misma configuración.

En esta clase Terraform crea una VPC y tres instancias EC2. Un bootstrap mínimo instala Ansible en el control node. A partir de ahí, Ansible configura el propio controller y administra dos servidores web.

## Laboratorios

| LAB | Guía | Foco |
|---|---|---|
| LAB01 | `guias/guia-ansible-lab01-control-node-terraform.md` | Infraestructura modular, claves SSH, bootstrap y control node |
| LAB02 | `guias/guia-ansible-lab02-gestion-servidores.md` | Inventario, módulos, playbooks, handlers, idempotencia y drift |

## Arquitectura

```text
Notebook del alumno
  | Terraform + SSH (student_cidr)
  v
VPC / subnet pública
  +-- Ansible control node (Ubuntu 24.04)
  |     Ansible + Git + jq
  |       |
  |       | SSH por IP privada
  |       v
  +-- web01 (Ubuntu 24.04 + Nginx)
  +-- web02 (Ubuntu 24.04 + Nginx)
```

Los managed nodes tienen IP pública para validar HTTP sin NAT Gateway, pero su puerto SSH sólo acepta conexiones desde el Security Group del control node.

## Estructura

```text
.
├── guias/
├── terraform/ansible-aws-lab/
│   ├── modules/ec2-instance/
│   └── user-data/
├── ansible/
│   ├── inventories/lab/group_vars/
│   ├── playbooks/
│   └── templates/
└── scripts/
```

## Requisitos

En la notebook o WSL:

- Git
- AWS CLI con una cuenta de laboratorio autorizada
- Terraform `>= 1.6`
- OpenSSH (`ssh`, `scp`, `ssh-keygen`)
- Bash y `jq`

El control node instala Ansible mediante User Data.

## Inicio rápido

```bash
git clone https://github.com/nicopannu/curso-cloud-formatec-c2-2026.git
cd curso-cloud-formatec-c2-2026
git checkout m3-c2-lab
./scripts/validate-lab.sh
```

Seguir primero LAB01 y después LAB02. No ejecutar `apply` sin confirmar la cuenta AWS y el costo temporal de tres instancias EC2.

## Repositorio personal

Usar el repositorio personal del curso y una branch llamada:

```text
m3-c2-lab
```

Estructura de entrega sugerida:

```text
lab01/
lab02/
```

No subir `.terraform/`, state, `terraform.tfvars`, inventarios con IP reales, claves SSH, credenciales ni logs con información sensible.

## Seguridad y costo

- Terraform registra únicamente claves públicas.
- Las claves privadas permanecen fuera del repositorio y del state.
- SSH al controller se limita a `student_cidr`.
- SSH a los managed nodes se limita al Security Group del controller.
- El laboratorio usa tres instancias pequeñas y recursos de red sin NAT Gateway.
- Ejecutar `terraform destroy` al terminar.
