# Formatec Cloud 2026 — M3-C2 Gestión de configuración con Ansible

Repositorio del curso **Arquitectura e Ingeniería Cloud | C2**.

Profesor: Nicolas Pannucio

Branch: `m3-c2-lab`

## Escenario

CloudCuyo ya puede crear infraestructura repetible con Terraform. El nuevo problema aparece después del aprovisionamiento: instalar paquetes, crear usuarios, distribuir archivos y mantener varios servidores con una configuración controlada.

LAB01 y LAB02 comienzan con una VPC, un control node y dos servidores web. LAB03 amplía el grupo con `web03`, personaliza el saludo de cada nodo y aplica una modificación dirigida solamente al servidor nuevo.

## Laboratorios

| LAB | Guía | Foco |
|---|---|---|
| LAB01 | `guias/guia-ansible-lab01-control-node-terraform.md` | Infraestructura modular, claves SSH, bootstrap y control node |
| LAB02 | `guias/guia-ansible-lab02-gestion-servidores.md` | Inventario, módulos, playbooks, handlers, idempotencia y drift |
| LAB03 | `guias/guia-ansible-lab03-cambios-dirigidos-web03.md` | Nueva EC2, variables por host, `--limit`, handler y cambio dirigido |

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
  +-- web03 (agregado en LAB03)
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
│   ├── inventories/lab/host_vars/
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

El control node instala Ansible mediante User Data. El entorno Codespaces tambien incluye Ansible para ejecutar validaciones locales de sintaxis.

## Opción web con GitHub Codespaces

Esta branch incluye `.devcontainer/devcontainer.json` con Git, AWS CLI, Terraform, Ansible, Python, `jq`, OpenSSH y extensiones para Terraform y Ansible.

### Abrir el laboratorio

1. Abrir <https://github.com/nicopannu/curso-cloud-formatec-c2-2026>.
2. Seleccionar la branch `m3-c2-lab`.
3. Presionar **Code** y abrir la pestaña **Codespaces**.
4. Presionar **Create codespace on m3-c2-lab**.
5. Esperar a que finalice la construcción.

También podés iniciar directamente el entorno desde este enlace:

<https://codespaces.new/nicopannu/curso-cloud-formatec-c2-2026?ref=m3-c2-lab>

GitHub mostrará la branch `m3-c2-lab` antes de crear el Codespace. Confirmala y usá la máquina mínima disponible para el laboratorio.

Verificar el entorno:

```bash
git branch --show-current
git --version
aws --version
terraform version
ansible --version
ansible-playbook --version
ssh -V
jq --version
```

Si una herramienta no aparece, abrir la paleta con `Ctrl+Shift+P` y ejecutar **Codespaces: Rebuild Container**.

### Configurar AWS

Usar preferentemente acceso temporal. Con AWS IAM Identity Center:

```bash
aws configure sso --profile curso
aws sso login --profile curso --use-device-code
export AWS_PROFILE=curso
aws sts get-caller-identity
```

Si recibiste credenciales temporales, cargarlas desde <https://github.com/settings/codespaces> como secretos autorizados solamente para el repositorio necesario:

- `AWS_ACCESS_KEY_ID`
- `AWS_SECRET_ACCESS_KEY`
- `AWS_SESSION_TOKEN`
- `AWS_DEFAULT_REGION` con valor `us-east-1`

Después de crear o actualizar secretos, detener y reiniciar el Codespace. Verificar sin mostrar valores:

```bash
aws configure list
aws sts get-caller-identity
```

No guardar credenciales en `.devcontainer/`, Terraform, inventarios, scripts, archivos `.env`, capturas ni commits. Los secretos de Codespaces se autorizan por repositorio, no por branch.

### Calcular `student_cidr` desde Codespaces

La IP que debe autorizarse es la IP pública de salida del Codespace, no la IP de la notebook. Obtenerla desde la terminal web:

```bash
CODESPACE_IP="$(curl -fsS https://checkip.amazonaws.com | tr -d '\r\n')"
printf '%s/32\n' "$CODESPACE_IP"
```

Usar el valor terminado en `/32` para `student_cidr` en `terraform.tfvars`. La IP puede cambiar después de detener o reconstruir el Codespace. Al retomar la práctica, volver a calcularla y revisar `terraform plan`; si cambió, actualizar `student_cidr` antes de intentar SSH o HTTP.

### Claves, state y persistencia

Generar las claves del lab dentro de `$HOME/.ssh` siguiendo LAB01. Las claves privadas nunca deben entrar al repositorio ni al state.

Este lab usa state local. Mientras existan recursos AWS:

- no eliminar el Codespace;
- no perder el directorio de trabajo;
- conservar las claves privadas en `$HOME/.ssh`;
- detener el Codespace cuando hagas una pausa;
- ejecutar `terraform destroy` y verificar la limpieza antes de eliminarlo.

Eliminar el Codespace antes de destruir puede hacerte perder el state y las claves necesarias para operar el entorno. **Stop** conserva el disco; **Delete** lo elimina.

Antes de cerrar una sesión:

```bash
git status
```

Guardar en el repositorio personal solamente los archivos permitidos por las guías. No subir `.terraform/`, state, `terraform.tfvars`, inventarios con IP reales, claves SSH ni credenciales.

### Validar el material

Desde la raíz:

```bash
./scripts/validate-lab.sh
```

La validación revisa Terraform, Bash, estructura, YAML y sintaxis de los playbooks. No crea recursos AWS.

## Inicio rápido

```bash
git clone https://github.com/nicopannu/curso-cloud-formatec-c2-2026.git
cd curso-cloud-formatec-c2-2026
git checkout m3-c2-lab
./scripts/validate-lab.sh
```

Seguir LAB01, LAB02 y LAB03 en ese orden. No ejecutar `apply` sin confirmar la cuenta AWS. Los dos primeros labs utilizan tres EC2; LAB03 agrega temporalmente una cuarta instancia.

## Repositorio personal

Usar el repositorio personal del curso y una branch llamada:

```text
m3-c2-lab
```

Estructura de entrega sugerida:

```text
lab01/
lab02/
lab03/
```

No subir `.terraform/`, state, `terraform.tfvars`, inventarios con IP reales, claves SSH, credenciales ni logs con información sensible.

## Seguridad y costo

- Terraform registra únicamente claves públicas.
- Las claves privadas permanecen fuera del repositorio y del state.
- SSH al controller se limita a `student_cidr`.
- SSH a los managed nodes se limita al Security Group del controller.
- LAB01 y LAB02 usan tres instancias pequeñas; LAB03 agrega una cuarta EC2 temporal.
- Los recursos de red no incluyen NAT Gateway.
- Ejecutar `terraform destroy` al terminar.
