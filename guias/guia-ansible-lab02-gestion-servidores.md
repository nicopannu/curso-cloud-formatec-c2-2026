# Guía Ansible LAB02: gestión de configuración sobre servidores AWS

**Módulo:** M3-C2 — Gestión de configuración con Ansible

**Duración estimada:** 75 a 90 minutos

**Dependencia:** LAB01 aplicado y control node operativo

---

## 1. Contexto

CloudCuyo dispone de dos servidores vacíos. Configurarlos uno por uno mediante SSH produciría diferencias difíciles de detectar y repetir. En este laboratorio el control node aplicará el mismo estado deseado sobre `web01` y `web02`.

La pregunta central es:

> ¿Cómo podemos declarar, verificar y recuperar una configuración homogénea en varios servidores?

## 2. Objetivos de aprendizaje

Al finalizar podrás:

1. Construir un inventario con grupos, aliases y variables de conexión.
2. Validar SSH y Python remoto con el módulo `ping`.
3. Usar facts para generar contenido específico por host.
4. Aplicar módulos idempotentes para paquetes, usuarios, archivos y servicios.
5. Utilizar templates y handlers.
6. Interpretar `ok`, `changed`, `failed` y `unreachable`.
7. Demostrar idempotencia con una segunda ejecución.
8. Detectar y corregir configuration drift.
9. Diferenciar conectividad Ansible de funcionamiento HTTP.

## 3. Arquitectura

```text
Ansible control node
  |
  | inventory + playbook + clave managed
  | SSH privado
  +------------------+
  v                  v
web01              web02
Nginx              Nginx
```

Terraform continúa siendo dueño del ciclo de vida de EC2 y red. Ansible es dueño de la configuración del sistema operativo y Nginx.

## 4. Alcance

### Incluido

- Inventario estático generado desde outputs Terraform.
- `ansible.cfg` y variables de grupo.
- Módulos `apt`, `user`, `file`, `template` y `service`.
- Facts, handler, idempotencia y drift.
- Verificación HTTP por IP privada y pública.

### Fuera de alcance

- Inventario dinámico.
- Roles.
- Vault y secretos de aplicación.
- Despliegues rolling o estrategias de producción.
- Observabilidad centralizada.

## 5. Prerrequisitos

- LAB01 aplicado.
- Control node accesible.
- Clave `formatec-managed` copiada al controller con modo `0600`.
- Repositorio en la misma revisión tanto en notebook como controller.

Desde la notebook:

```bash
export AWS_PROFILE=curso
cd curso-cloud-formatec-c2-2026/terraform/ansible-aws-lab
terraform output
```

## Actividades

Las actividades siguientes conectan los outputs de Terraform con el inventario y comprueban el estado administrado por Ansible.

## 6. Generar el inventario desde Terraform

Desde la raíz del repositorio en la notebook:

```bash
./scripts/render-inventory.sh
cat ansible/inventories/lab/hosts.ini
```

El script lee el state local y utiliza las IP privadas de `managed_private_ips`. No copies el state al controller.

Obtener la IP del controller y copiar el inventario:

```bash
CONTROL_IP="$(terraform -chdir=terraform/ansible-aws-lab output -raw ansible_control_public_ip)"
scp -i ~/.ssh/formatec-control \
  ansible/inventories/lab/hosts.ini \
  ubuntu@"$CONTROL_IP":~/curso-cloud-formatec-c2-2026/ansible/inventories/lab/hosts.ini
```

### Checkpoint 1

Explica:

1. ¿Por qué el state permanece en la notebook?
2. ¿Por qué el inventario usa IP privada?
3. ¿Qué Security Group permite este tráfico?
4. ¿Qué diferencia existe entre alias `web01` y `ansible_host`?

## 7. Registrar host keys

Conéctate al controller:

```bash
ssh -i ~/.ssh/formatec-control ubuntu@"$CONTROL_IP"
cd ~/curso-cloud-formatec-c2-2026/ansible
chmod 600 ~/.ssh/formatec-managed
```

Revisa el inventario:

```bash
ansible-inventory --graph
ansible-inventory --host web01
```

Registra las claves de los managed nodes antes de automatizar:

```bash
for ip in $(awk '/ansible_host=/{for(i=1;i<=NF;i++) if($i ~ /^ansible_host=/){split($i,a,"="); print a[2]}}' inventories/lab/hosts.ini); do
  ssh-keyscan -H "$ip" >> ~/.ssh/known_hosts
done
chmod 600 ~/.ssh/known_hosts
```

## 8. Validar conectividad

```bash
ansible web -m ansible.builtin.ping
ansible web -m ansible.builtin.setup -a 'filter=ansible_distribution*'
```

`ping` valida SSH, autenticación y Python remoto. No valida Nginx ni el puerto HTTP.

Si un host aparece `UNREACHABLE`, no ejecutes todavía el playbook: corrige inventario, clave o red.

## 9. Leer el playbook

```bash
sed -n '1,240p' playbooks/site.yml
```

Identifica:

- grupo objetivo;
- uso de `become`;
- módulos FQCN;
- variables de `group_vars/web.yml`;
- template con facts;
- tarea que notifica al handler;
- estado deseado del servicio.

### Checkpoint 2

¿Por qué es preferible `ansible.builtin.apt` a ejecutar `apt-get` dentro de `shell`? ¿Qué información puede comparar Ansible antes de decidir si cambia algo?

## 10. Primera ejecución

```bash
ansible-playbook playbooks/site.yml
```

Resultado esperado:

- Nginx instalado;
- usuario `cloudcuyo` creado;
- `/opt/cloudcuyo` presente;
- configuración de Nginx desplegada;
- página diferente en cada host por sus facts;
- Nginx iniciado y habilitado;
- handler ejecutado si cambió su configuración.

Guarda el `PLAY RECAP`.

## 11. Verificar desde el controller

```bash
ansible web -m ansible.builtin.service -a 'name=nginx' -b
ansible web -m ansible.builtin.uri -a 'url=http://127.0.0.1 return_content=true'
```

También puedes usar las IP privadas:

```bash
for ip in $(awk '/ansible_host=/{for(i=1;i<=NF;i++) if($i ~ /^ansible_host=/){split($i,a,"="); print a[2]}}' inventories/lab/hosts.ini); do
  curl -fsS "http://$ip" | grep -E 'Host de inventario|IP privada'
done
```

## 12. Segunda ejecución: idempotencia

Sin modificar archivos:

```bash
ansible-playbook playbooks/site.yml
```

Resultado esperado:

- `failed=0`;
- `unreachable=0`;
- `changed=0` en ambos hosts;
- el handler no vuelve a ejecutarse.

Si una tarea cambia siempre, revisa si realmente declara estado o ejecuta una acción imperativa.

## 13. Modo check y diff

Después de tener una configuración base funcional:

```bash
ansible-playbook playbooks/site.yml --check --diff
```

Debe anticipar cero cambios.

En una máquina nueva, `--check` puede no completar tareas que dependen de un paquete o directorio que todavía no existe. No reemplaza una prueba real.

## 14. Simular y reparar drift

Usa una acción imperativa solamente para producir una desviación controlada en `web01`:

```bash
ansible web01 -b -m ansible.builtin.shell \
  -a "printf '<h1>cambio manual</h1>\n' > /var/www/html/index.html"
```

Detecta la diferencia:

```bash
ansible-playbook playbooks/site.yml --check --diff --limit web01
```

Repara:

```bash
ansible-playbook playbooks/site.yml --limit web01
ansible-playbook playbooks/site.yml --check --diff --limit web01
```

La última ejecución debe anticipar cero cambios.

## 15. Probar recuperación del servicio

Detén Nginx de forma controlada:

```bash
ansible web01 -b -m ansible.builtin.command -a 'systemctl stop nginx'
```

Verifica que HTTP falla y vuelve a aplicar estado:

```bash
ansible web01 -m ansible.builtin.uri -a 'url=http://127.0.0.1 status_code=200'
ansible-playbook playbooks/site.yml --limit web01
ansible web01 -m ansible.builtin.uri -a 'url=http://127.0.0.1 status_code=200'
```

La primera prueba HTTP debe fallar; la segunda debe responder `200`.

## 16. Probar el handler

Edita `templates/cloudcuyo-security.conf.j2` y agrega:

```nginx
keepalive_timeout 30;
```

Ejecuta:

```bash
ansible-playbook playbooks/site.yml --check --diff
ansible-playbook playbooks/site.yml
```

Observa que la tarea de configuración cambia y notifica una única recarga de Nginx por host. Una nueva ejecución sin cambios no debe disparar el handler.

Para dejar el repositorio igual que al inicio, elimina la línea agregada y ejecuta el playbook otra vez.

## 17. Verificar HTTP desde la notebook

Sal del controller. Desde la raíz del repositorio local:

```bash
terraform -chdir=terraform/ansible-aws-lab output -json managed_public_ips | jq -r '.[]'
```

Prueba cada IP pública:

```bash
for ip in $(terraform -chdir=terraform/ansible-aws-lab output -json managed_public_ips | jq -r '.[]'); do
  curl -fsS "http://$ip" | grep -E 'Host de inventario|Hostname del sistema|IP privada'
done
```

Esta prueba valida el camino HTTP permitido por `student_cidr`. No demuestra balanceo ni alta disponibilidad.

## 18. Troubleshooting

### `UNREACHABLE`

```bash
ansible-inventory --host web01
ls -l ~/.ssh/formatec-managed
ssh -i ~/.ssh/formatec-managed ubuntu@IP_PRIVADA
```

Comprueba que ejecutas los comandos desde el controller.

### `Host key verification failed`

Registra la clave con `ssh-keyscan` y verifica que no estés aceptando una clave inesperada después de reutilizar una IP.

### Error de `apt` bloqueado

Cloud-init puede estar instalando paquetes. Espera y revisa:

```bash
cloud-init status --wait
```

### Nginx no recarga

```bash
ansible web -b -m ansible.builtin.command -a 'nginx -t'
ansible web -b -m ansible.builtin.command -a 'journalctl -u nginx --no-pager -n 30'
```

## 19. Entregables

Guardar en `lab02/`:

- `ansible.cfg`;
- inventario anonimizado o `.example`, sin IP públicas reales;
- `group_vars/web.yml`;
- playbooks y templates;
- recap de primera y segunda ejecución;
- evidencia de `ping` en ambos hosts;
- respuesta HTTP identificando ambos nodos;
- diff y reparación del drift;
- evidencia de recuperación de Nginx;
- explicación breve de idempotencia y handler.

## 20. Criterios de evaluación

- 20%: inventario y conectividad correctos.
- 30%: uso adecuado de módulos, variables, templates y handler.
- 20%: servicio instalado, iniciado y habilitado en ambos nodos.
- 15%: segunda ejecución idempotente.
- 10%: drift detectado y reparado.
- 5%: evidencias seguras y explicación técnica.

## 21. Limpieza

Desde la notebook, no desde el controller:

```bash
cd terraform/ansible-aws-lab
terraform destroy
terraform state list
```

`terraform state list` debe quedar vacío.

Opcionalmente elimina las claves temporales locales después de confirmar que no las reutilizas:

```bash
rm ~/.ssh/formatec-control ~/.ssh/formatec-control.pub
rm ~/.ssh/formatec-managed ~/.ssh/formatec-managed.pub
```

No elimines otras claves del directorio `~/.ssh`.
