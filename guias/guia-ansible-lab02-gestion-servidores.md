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

![Arquitectura del laboratorio: el control node usa Ansible para configurar web01 y web02](../assets/diagramas/m3-c2-ansible-terraform-aws.png)

[Ver imagen en SVG](../assets/diagramas/m3-c2-ansible-terraform-aws.svg) · [Abrir fuente editable en Draw.io](../assets/diagramas/m3-c2-ansible-terraform-aws.drawio)

En LAB02 el recorrido principal es el flujo verde del diagrama: el controller lee el inventario y se conecta por SSH a las IP privadas de `web01` y `web02`.

Terraform continúa siendo dueño del ciclo de vida de EC2 y red. Ansible es dueño de la configuración del sistema operativo y Nginx.

El Security Group managed permite HTTP público desde `student_cidr` y HTTP privado desde el Security Group del controller. Esto permite validar la aplicación tanto desde la notebook como desde el nodo que ejecuta Ansible.

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

Desde la notebook, confirma nuevamente el perfil y los outputs.

### Bash o WSL

```bash
export AWS_PROFILE=curso
export AWS_REGION=us-east-1
cd curso-cloud-formatec-c2-2026/terraform/ansible-aws-lab
terraform output
```

### PowerShell

```powershell
$env:AWS_PROFILE = "curso"
$env:AWS_REGION = "us-east-1"
Set-Location curso-cloud-formatec-c2-2026\terraform\ansible-aws-lab
terraform output
```

**Por qué se hace así:** LAB02 reutiliza la infraestructura de LAB01. Los outputs confirman que el state local todavía contiene el controller y los managed nodes correctos.

## Actividades

Las actividades siguientes conectan los outputs de Terraform con el inventario y comprueban el estado administrado por Ansible.

## 6. Generar el inventario desde Terraform

Desde la raíz del repositorio en la notebook, genera el inventario.

### Bash o WSL

```bash
./scripts/render-inventory.sh
cat ansible/inventories/lab/hosts.ini
```

### PowerShell

```powershell
$managed = terraform -chdir=terraform/ansible-aws-lab `
  output -json managed_private_ips | ConvertFrom-Json

$webHosts = $managed.PSObject.Properties |
  Sort-Object Name |
  ForEach-Object { "{0} ansible_host={1}" -f $_.Name, $_.Value }

$inventory = @"
[control]
localhost ansible_connection=local

[web]
$($webHosts -join "`n")

[web:vars]
ansible_user=ubuntu
ansible_ssh_private_key_file=~/.ssh/formatec-managed
"@

$inventoryPath = Join-Path (Get-Location) "ansible\inventories\lab\hosts.ini"
[System.IO.File]::WriteAllText(
  $inventoryPath,
  $inventory,
  [System.Text.UTF8Encoding]::new($false)
)
Get-Content $inventoryPath
```

El script Bash y la alternativa PowerShell leen el state local y utilizan las IP privadas de `managed_private_ips`. No copies el state al controller.

**Por qué se hace así:** Terraform conoce las IP creadas y Ansible necesita esas IP como destinos. Generar el inventario desde outputs evita transcribir direcciones manualmente. El controller recibe sólo los datos de conexión, no el state completo.

Obtén la IP del controller y copia únicamente el inventario generado.

### Bash o WSL

```bash
CONTROL_IP="$(terraform -chdir=terraform/ansible-aws-lab output -raw ansible_control_public_ip)"
scp -i ~/.ssh/formatec-control \
  ansible/inventories/lab/hosts.ini \
  ubuntu@"$CONTROL_IP":~/curso-cloud-formatec-c2-2026/ansible/inventories/lab/hosts.ini
```

### PowerShell

```powershell
$CONTROL_IP = terraform -chdir=terraform/ansible-aws-lab `
  output -raw ansible_control_public_ip

scp -i "$HOME\.ssh\formatec-control" `
  "ansible\inventories\lab\hosts.ini" `
  "ubuntu@${CONTROL_IP}:~/curso-cloud-formatec-c2-2026/ansible/inventories/lab/hosts.ini"
```

**Por qué se hace así:** `scp` usa la clave de acceso al controller para transferir un archivo concreto. No se copia `.terraform/` ni el state porque Ansible necesita conocer hosts, no controlar el ciclo de vida de AWS.

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

Estos comandos se ejecutan dentro del controller Ubuntu, aunque hayas usado PowerShell en la notebook.

**Por qué se hace así:** SSH verifica la identidad del servidor mediante su host key. Registrarla evita desactivar `host_key_checking` y permite detectar una identidad inesperada.

## 8. Validar conectividad

```bash
ansible web -m ansible.builtin.ping
ansible web -m ansible.builtin.setup -a 'filter=ansible_distribution*'
```

`ping` valida SSH, autenticación y Python remoto. No valida Nginx ni el puerto HTTP.

**Por qué se hace antes del playbook:** separa problemas de conexión de problemas de configuración. Si `ping` falla, todavía no corresponde investigar las tareas de Nginx.

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

**Por qué se usan módulos FQCN:** nombres como `ansible.builtin.apt` hacen explícita la colección y permiten consultar el estado actual antes de actuar. Un comando `shell` normalmente sólo informa si terminó, no si el estado ya era correcto.

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

**Por qué se guarda:** el recap resume cuántos hosts cambiaron, fallaron o quedaron inaccesibles y permite comparar la primera corrida con las siguientes.

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

**Por qué se ejecuta nuevamente:** una segunda corrida con `changed=0` demuestra que el playbook converge y puede repetirse sin cambios innecesarios.

## 13. Modo check y diff

Después de tener una configuración base funcional:

```bash
ansible-playbook playbooks/site.yml --check --diff
```

Debe anticipar cero cambios.

En una máquina nueva, `--check` puede no completar tareas que dependen de un paquete o directorio que todavía no existe. No reemplaza una prueba real.

**Por qué se usa después de una ejecución real:** con la configuración base presente, `--check --diff` puede comparar archivos y estados sin simular toda la instalación inicial.

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

**Por qué se introduce drift:** permite comprobar que Ansible no sólo instala una configuración inicial; también detecta y corrige cambios posteriores.

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

**Por qué se prueba por separado:** `ansible ping` puede funcionar aunque Nginx esté detenido. Conectividad del nodo y salud de la aplicación son estados diferentes.

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

**Por qué se usa un handler:** la recarga sólo es necesaria cuando cambia la configuración. Ejecutarla siempre agregaría acciones innecesarias.

Para dejar el repositorio igual que al inicio, elimina la línea agregada y ejecuta el playbook otra vez.

## 17. Verificar HTTP desde la notebook

Sal del controller. Desde la raíz del repositorio local:

```bash
terraform -chdir=terraform/ansible-aws-lab output -json managed_public_ips | jq -r '.[]'
```

Prueba cada IP pública.

### Bash o WSL

```bash
for ip in $(terraform -chdir=terraform/ansible-aws-lab output -json managed_public_ips | jq -r '.[]'); do
  curl -fsS "http://$ip" | grep -E 'Host de inventario|Hostname del sistema|IP privada'
done
```

### PowerShell

```powershell
$publicIps = terraform -chdir=terraform/ansible-aws-lab `
  output -json managed_public_ips | ConvertFrom-Json

$publicIps.PSObject.Properties | ForEach-Object {
  $response = Invoke-WebRequest -UseBasicParsing -Uri "http://$($_.Value)"
  "{0}: HTTP {1}" -f $_.Name, $response.StatusCode
  $response.Content
}
```

**Por qué se prueba desde la notebook:** esta llamada recorre la regla HTTP autorizada por `student_cidr`. La prueba interna y la pública verifican caminos de red diferentes.

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

## 20. Limpieza

Si continuarás inmediatamente con LAB03, no destruyas todavía la infraestructura. LAB03 reutiliza el controller, `web01`, `web02` y el mismo state para incorporar `web03`.

Desde la notebook, no desde el controller. Los comandos Terraform son iguales en Bash, WSL y PowerShell:

```bash
cd terraform/ansible-aws-lab
terraform destroy
terraform state list
```

**Por qué se destruye desde la notebook:** allí permanece el state que conoce recursos y dependencias. El controller administra configuración, pero no es dueño de la infraestructura.

`terraform state list` debe quedar vacío.

Opcionalmente elimina las claves temporales locales después de confirmar que no las reutilizas.

### Bash o WSL

```bash
rm ~/.ssh/formatec-control ~/.ssh/formatec-control.pub
rm ~/.ssh/formatec-managed ~/.ssh/formatec-managed.pub
```

### PowerShell

```powershell
Remove-Item "$HOME\.ssh\formatec-control", "$HOME\.ssh\formatec-control.pub"
Remove-Item "$HOME\.ssh\formatec-managed", "$HOME\.ssh\formatec-managed.pub"
```

No elimines otras claves del directorio `~/.ssh` o `$HOME\.ssh`.
