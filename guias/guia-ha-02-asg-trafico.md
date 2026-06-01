# Guia HA-02: Alta Disponibilidad - Auto Scaling Group + Traffic Generator

**Objetivo:** Reemplazar las 2 EC2 fijas del Lab HA-01 por un Auto Scaling Group que ajusta la capacidad automaticamente segun la carga real. Desplegar un generador de trafico via CloudFormation y observar scale-out bajo carga y scale-in al detenerla.

**Duracion estimada:** 2-3 horas

**Módulo:** Módulo 2 — Clase 2: Alta Disponibilidad

---

## Contexto

En el Lab HA-01, CloudCuyo reemplazo el NGINX `lb01` por un ALB administrado con dos nodos fijos. Eso soluciono el punto unico de falla, pero no el problema de capacidad: si llegan mas usuarios de los que dos instancias `t3.micro` pueden manejar, las instancias se saturan y los tiempos de respuesta aumentan. La unica solucion seria agregar instancias manualmente, lo cual:

1. Requiere intervencion humana
2. Introduce latencia entre deteccion del problema y resolucion
3. Es dificil de hacer a las 3am cuando el trafico aumenta inesperadamente

Con un **Auto Scaling Group (ASG)**, AWS agrega y quita instancias automaticamente segun metricas de carga. El ALB del Lab HA-01 queda como esta: el ASG simplemente registra y desregistra instancias en el mismo Target Group.

Este lab tambien introduce un **generador de trafico** desplegado via CloudFormation. Sirve para simular carga real de manera controlada, sin depender de herramientas externas ni de scripts manuales.

---

## Arquitectura objetivo

```
                         Internet
                            |
                           IGW
                            |
              +-------------+-------------+
              |                           |
   +----------+-----------+  +------------+----------+
   | Public Subnet AZ-A   |  | Public Subnet AZ-B    |
   |                      |  |                       |
   | +------------------+ |  | +------------------+  |
   | | Traffic Generator| |  | |                  |  |
   | | (EC2 con ab)     | |  | |                  |  |
   | +--------+---------+ |  | +------------------+  |
   |          |           |  |                       |
   |   +------+-------+   |  |                       |
   |   | ALB node     |   |  |   +---------------+   |
   |   | (existente)  |   |  |   | ALB node      |   |
   |   +------+-------+   |  |   | (existente)   |   |
   +----------|------------+  +----------|------------+
              |                          |
              +----------+---------------+
                         |
              +----------+-------------+
              |    Target Group        |
              |   (existente del Lab HA-01)    |
              +-----+------+------+---+
                    |      |      |
                    |      |      |
              +-----+  +---+--+  +-+----+
              |        |      |        |
+------+------+--+  +--+------+--+  +--+------+--+  (hasta 4)
| Public Sub AZ-A  |  | Public Sub AZ-A  |  | Public Sub AZ-B  |
|                  |  |                  |  |                  |
| +-------------+  |  | +-------------+  |  | +-------------+  |
| | api-asg-x   |  |  | | api-asg-x   |  |  | | api-asg-x   |  |
| | (ASG inst.) |  |  | | (ASG inst.) |  |  | | (ASG inst.) |  |
| +-------------+  |  | +-------------+  |  | +-------------+  |
+------------------+  +------------------+  +------------------+
                            ^
                     Auto Scaling Group
                     Desired=2  Min=2  Max=4
                     Scale-out: >100 req/target/min
                     Scale-in:  <100 req/target/min
```

---

## Pre-requisitos

- **Lab HA-01 completado.** El ALB `cloudcuyo-api-alb` y el Target Group `cloudcuyo-api-tg` deben existir y estar funcionales.
- Si se elimino el stack `cloudcuyo-ha-lab1-nodes` al final del Lab HA-01, el ALB y TG pueden seguir existiendo de todos modos (el stack solo contenia las 2 EC2 fijas, no el ALB).
- Region: **us-east-1**

> **Antes de comenzar:** Verificar que el ALB `cloudcuyo-api-alb` y el Target Group `cloudcuyo-api-tg` existen en **EC2 > Load Balancers** y **EC2 > Target Groups**. Ambos deben aparecer en la lista. Si alguno no existe, volver al Lab HA-01 para recrearlo.

Tener a mano:
- ID de la VPC (VPC > Your VPCs)
- ID de la subnet publica AZ-A
- ID de la subnet publica AZ-B
- Nombre del Instance Profile SSM (`cloudcuyo-ssm-role`)
- DNS name del ALB (EC2 > Load Balancers > cloudcuyo-api-alb > columna DNS name)
- ARN del Target Group (EC2 > Target Groups > cloudcuyo-api-tg > columna ARN)
- ID del Security Group del ALB (`cloudcuyo-alb-sg`)
- El Security Group de los nodos del ASG se crea en la Fase 1.2 de este lab

---

## Fase 1: Eliminar los nodos fijos del Lab HA-01

Si el stack `cloudcuyo-ha-lab1-nodes` todavia existe (las 2 EC2 fijas siguen corriendo), se debe eliminar antes de crear el ASG. No es posible tener dos conjuntos de targets en el mismo Target Group con diferente ciclo de vida.

> **¿Por que eliminar primero los nodos del Lab HA-01?** El Target Group tiene registrados los dos nodos EC2 del stack anterior. Si creamos el ASG apuntando al mismo Target Group sin eliminar esos nodos primero, tendriamos instancias "viejas" compitiendo con las instancias del ASG. El stack se puede eliminar sin tocar el ALB ni el Target Group: son recursos independientes.

**Verificar si el stack existe:**

1. Ir a **CloudFormation > Stacks**
2. Buscar `cloudcuyo-ha-lab1-nodes` en la lista
3. Si aparece con estado `CREATE_COMPLETE`, proceder a eliminarlo

**Si el stack existe, eliminarlo:**

1. Seleccionar `cloudcuyo-ha-lab1-nodes`
2. Click **Delete** > confirmar
3. Esperar a que el stack desaparezca de la lista

**Verificar que el Target Group quede vacio:**

1. Ir a **EC2 > Target Groups > cloudcuyo-api-tg > Targets**
2. Debe aparecer sin targets registrados (o los targets en estado `draining` transitando a `deregistered`)
3. Esperar a que no queden instancias activas antes de continuar

### 1.2 Crear Security Group para los nodos del ASG

Al eliminar el stack `cloudcuyo-ha-lab1-nodes`, tambien se elimina el Security Group que ese stack habia creado para los nodos fijos. Por eso el ASG necesita un Security Group nuevo, creado manualmente y fuera del stack anterior.

> **¿Por que no reutilizar el `ApiNodeSgId` del Lab HA-01?** Ese SG pertenece al stack `cloudcuyo-ha-lab1-nodes`. Si se elimina el stack, CloudFormation elimina tambien el SG. Si el ASG usara ese SG, la eliminacion del stack fallaria o dejaria dependencias cruzadas. Crear un SG manual para el ASG deja claro que el ciclo de vida de los nodos autoscalados es independiente del stack de nodos fijos.

1. Ir a **EC2 > Security Groups > Create security group**
2. Configurar:
   - **Security group name:** `cloudcuyo-api-node-sg`
   - **Description:** `CloudCuyo API nodes - allow HTTP 5000 from ALB`
   - **VPC:** seleccionar la VPC del lab
3. En **Inbound rules > Add rule:**
   - **Type:** Custom TCP
   - **Port range:** `5000`
   - **Source:** seleccionar el Security Group `cloudcuyo-alb-sg`
4. En **Outbound rules:** dejar la regla por defecto `All traffic` hacia `0.0.0.0/0`
5. Click **Create security group**
6. Anotar el **Security Group ID**. Se usara en el Launch Template y en el stack del traffic generator como `ApiSgId`.

---

## Fase 2: Crear Launch Template

El Launch Template es el "molde" que el ASG usa para lanzar nuevas instancias. Define la AMI, el tipo de instancia, el security group, el IAM profile y el user-data con la instalacion de la API.

> **¿Que es un Launch Template?** Es la "receta" que el ASG usa para crear instancias nuevas. Contiene todo lo necesario para que cada instancia nueva sea identica a las anteriores: AMI, tipo de instancia, SG, IAM profile y script de arranque (UserData). Sin un Launch Template, el ASG no sabe como crear instancias. En versiones anteriores de AWS se usaban "Launch Configurations"; el Launch Template es su reemplazo moderno y mas flexible.

### 2.1 Crear Launch Template (AWS Console)

1. Ir a **EC2 > Launch Templates > Create launch template**
2. Configurar seccion **Launch template name and description:**
   - **Launch template name:** `cloudcuyo-api-lt`
   - **Template version description:** `CloudCuyo HA API - v1`
3. Configurar seccion **Application and OS Images (Amazon Machine Image):**
   - Click en **Quick Start**
   - Seleccionar **Amazon Linux**
   - En el selector, elegir **Amazon Linux 2023 AMI** (la mas reciente disponible)

> **¿Por que Amazon Linux 2023 y no otra AMI?** Amazon Linux 2023 tiene el SSM Agent preinstalado, lo que permite conectarse a las instancias via Systems Manager sin necesitar SSH ni una IP publica expuesta. Tambien tiene `dnf` como gestor de paquetes, que es mas moderno que `yum`. Para el lab es la opcion mas conveniente.

4. Configurar seccion **Instance type:** `t3.micro`
5. Configurar seccion **Key pair (login):** seleccionar `lab-key` (o dejar sin key pair si se usara solo SSM)
6. Configurar seccion **Network settings:**
   - **Firewall (security groups):** seleccionar `cloudcuyo-api-node-sg` (el SG creado en la Fase 1.2, que permite puerto 5000 desde el ALB)
7. Configurar seccion **Advanced details:**
   - **IAM instance profile:** seleccionar `cloudcuyo-ssm-role` (o el nombre del Instance Profile SSM)
   - **User data:** copiar y pegar el siguiente script completo en el campo User data:

> **¿Por que el User Data y no una AMI pre-configurada?** En un entorno de lab, el User Data permite ver exactamente que se instala sin necesidad de gestionar AMIs propias. En produccion se preferiria una AMI "baked" (pre-configurada) para reducir el tiempo de bootstrap de nuevas instancias de ~2 minutos a ~30 segundos. Para el lab, la visibilidad del proceso es mas importante que la velocidad.

> **¿Por que el systemd service usa `PLACEHOLDER_NODE` y luego `sed`?** Amazon Linux 2023 requiere IMDSv2 (token-based) para acceder a los metadatos de la instancia. Las variables `$INSTANCE_ID` y `$AZ` se obtienen durante el bootstrap, pero el archivo del servicio systemd se escribe con heredoc (comillas simples — bash no interpola variables en ese bloque). El truco es escribir `PLACEHOLDER_NODE` como valor temporario y luego reemplazarlo con `sed -i` usando la variable ya resuelta.

```bash
#!/bin/bash
set -e
exec > >(tee /var/log/user-data.log) 2>&1

dnf update -y
dnf install -y python3 python3-pip

TOKEN=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" \
  -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
INSTANCE_ID=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" \
  http://169.254.169.254/latest/meta-data/instance-id)
AZ=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" \
  http://169.254.169.254/latest/meta-data/placement/availability-zone)

mkdir -p /opt/cloudcuyo-api

cat > /opt/cloudcuyo-api/app.py << 'PYAPP'
import os, signal, threading, time
from flask import Flask, jsonify

app = Flask(__name__)

NODE    = os.getenv("APP_NODE", "unknown")
AZ_NAME = os.getenv("APP_AZ",   "unknown")

@app.get("/health")
def health():
    return jsonify({"node": NODE, "az": AZ_NAME, "status": "ok"})

@app.get("/api/v1/health")
def v1_health():
    return jsonify({"node": NODE, "az": AZ_NAME, "status": "ok", "version": "v1"})

@app.get("/api/v1/crash")
def crash():
    def _kill():
        time.sleep(0.1)
        os.kill(os.getpid(), signal.SIGTERM)
    threading.Thread(target=_kill).start()
    return jsonify({"node": NODE, "message": "crashing in 100ms"})

@app.get("/health/deep")
def deep_health():
    time.sleep(0.05)
    return jsonify({"node": NODE, "az": AZ_NAME, "status": "ok", "db": "simulated_ok"})

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000)
PYAPP

pip3 install flask gunicorn

cat > /etc/systemd/system/cloudcuyo-api.service << 'SYSTEMD'
[Unit]
Description=CloudCuyo HA Demo API
After=network-online.target
[Service]
WorkingDirectory=/opt/cloudcuyo-api
Environment=APP_NODE=PLACEHOLDER_NODE
Environment=APP_AZ=PLACEHOLDER_AZ
ExecStart=/usr/local/bin/gunicorn --bind 0.0.0.0:5000 --workers 2 app:app
Restart=always
RestartSec=3
[Install]
WantedBy=multi-user.target
SYSTEMD
sed -i "s/PLACEHOLDER_NODE/$INSTANCE_ID/" /etc/systemd/system/cloudcuyo-api.service
sed -i "s/PLACEHOLDER_AZ/$AZ/" /etc/systemd/system/cloudcuyo-api.service

systemctl daemon-reload
systemctl enable cloudcuyo-api
systemctl start cloudcuyo-api
```

8. Click **Create launch template**

### 2.2 Verificar el Launch Template

1. Ir a **EC2 > Launch Templates**
2. Seleccionar `cloudcuyo-api-lt`
3. Pestana **Details** → verificar AMI ID, Instance type y IAM instance profile
4. Pestana **User data** → verificar que el script este completo

---

## Fase 3: Crear Auto Scaling Group

### 3.1 Crear ASG (AWS Console)

1. Ir a **EC2 > Auto Scaling Groups > Create Auto Scaling group**
2. **Paso 1 - Choose launch template:**
   - **Name:** `cloudcuyo-api-asg`
   - **Launch template:** `cloudcuyo-api-lt`
   - Dejar version en `Default (1)`
   - Click **Next**
3. **Paso 2 - Choose instance launch options:**
   - **VPC:** seleccionar la VPC del lab
   - **Availability Zones and subnets:** seleccionar las dos subnets publicas:
     - `cloudcuyo-public-us-east-1a` (AZ-A)
     - `cloudcuyo-public-us-east-1b` (AZ-B)
   - Click **Next**

> **¿Por que subnets publicas y no privadas?** Las instancias del ASG necesitan acceso a internet para que el SSM Agent funcione (se comunica con el servicio SSM en internet) y para que el bootstrap descargue paquetes. Como no tenemos NAT Gateway, la unica opcion que tiene salida a internet es la subnet publica. El trafico de usuarios llega a traves del ALB, y el SG protege los nodos de acceso directo.

4. **Paso 3 - Configure advanced options:**
   - En **Load balancing:**
     - Seleccionar **Attach to an existing load balancer**
     - Seleccionar **Choose from your load balancer target groups**
     - Target group: `cloudcuyo-api-tg`
   - En **Health checks:**
     - **Health check type:** `EC2` (solo EC2 por ahora — se cambia en Lab HA-03)
     - **Health check grace period:** `120` segundos
   - En **Monitoring / Additional settings** (si aparece en esta pantalla):
     - Habilitar **Group metrics collection within CloudWatch**
   - Click **Next**

> **¿Por que Health check type EC2 por ahora?** Intencionalmente. El Lab HA-03 demuestra que pasa cuando se deja en EC2 (no detecta fallas de proceso) y luego cambia a ELB (si las detecta). Si ya lo configuramos en ELB ahora, perdemos el experimento del Lab 3.

> **¿Por que Health check grace period de 120 segundos?** Cuando el ASG lanza una instancia nueva, el bootstrap (dnf update + pip install + arranque del servicio) tarda entre 60 y 90 segundos. Si el health check empieza inmediatamente, la instancia aparece como Unhealthy porque todavia no esta lista, el ASG la reemplaza... y asi en loop. Los 120 segundos dan tiempo suficiente para que la instancia arranque antes de ser evaluada.

> **¿Por que asociar el ASG al Target Group aqui?** Al asociarlo durante la creacion, el ASG automaticamente registra cada instancia nueva en el Target Group cuando pasa a `InService`, y la desregistra cuando la termina. Sin esta asociacion, habria que registrar/desregistrar manualmente cada instancia, lo que anula el proposito del ASG.

> **¿Por que habilitar group metrics?** El Lab HA-03 crea un dashboard con metricas del ASG como `GroupDesiredCapacity` y `GroupInServiceInstances`. Si la recoleccion de metricas de grupo queda deshabilitada, esas metricas no aparecen en CloudWatch y el alumno no puede completar el dashboard.

5. **Paso 4 - Configure group size and scaling:**
   - **Desired capacity:** `2`
   - **Minimum capacity:** `2`
   - **Maximum capacity:** `4`
   - **Automatic scaling:** `No scaling policies` por ahora (se agrega en Fase 4)
   - Click **Next**

> **¿Que significan Desired, Minimum y Maximum?**
> - **Desired (2):** cuantas instancias el ASG quiere mantener en este momento. Al crearlo, arranca 2.
> - **Minimum (2):** el ASG nunca bajara de 2 instancias, aunque el trafico sea cero. Garantiza que siempre hay capacidad base disponible.
> - **Maximum (4):** el ASG nunca superara 4 instancias, aunque la demanda lo pida. Protege contra costos inesperados o loops de escalado.

6. **Paso 5 - Add notifications:** omitir, click **Next**
7. **Paso 6 - Add tags:**
   - Agregar tag: `Key=Lab, Value=ha-02`
   - Marcar **Tag new instances** para que las instancias hereden el tag
   - Click **Next**
8. **Paso 7 - Review:** verificar configuracion y click **Create Auto Scaling group**

### 3.2 Verificar que el ASG lance las instancias

1. Ir a **EC2 > Auto Scaling Groups > cloudcuyo-api-asg**
2. Pestana **Activity** → deberian aparecer 2 eventos "Launching a new EC2 instance"
3. Pestana **Instance management** → esperar a que las 2 instancias queden en estado `InService`
4. Ir a **EC2 > Target Groups > cloudcuyo-api-tg > Targets** → esperar a estado `Healthy` en ambas

> El proceso completo (arranque de instancia + user-data + primera vez en Healthy) toma aproximadamente 2-3 minutos. El health check grace period de 120 segundos asegura que el ASG no marque las instancias como Unhealthy mientras la API esta iniciando.

### 3.3 Verificar metricas de grupo del ASG

1. Ir a **EC2 > Auto Scaling Groups > cloudcuyo-api-asg**
2. Abrir la pestana **Monitoring**
3. Verificar que las metricas de grupo esten habilitadas
4. Si aparece un boton como **Enable group metrics collection** o **Edit monitoring**, habilitar las metricas del grupo

> Estas metricas no son necesarias para escalar, pero si para el dashboard del Lab HA-03. Si no se habilitan, en CloudWatch no apareceran metricas como `GroupDesiredCapacity` o `GroupInServiceInstances`.

### Troubleshooting de la Fase 3

| Sintoma | Posible causa | Correccion |
|---|---|---|
| Instancias no pasan de `Pending` a `InService` | User-data falla o SSM profile incorrecto | Conectarse via SSM y revisar `/var/log/user-data.log` |
| Targets en `Unhealthy` tras el grace period | Puerto 5000 no accesible o API no arranco | Revisar SG y logs de systemd via SSM: `journalctl -u cloudcuyo-api` |
| ASG no lanza instancias | Cuota de instancias alcanzada | Verificar en EC2 > Limits |

---

## Fase 4: Crear Scaling Policy

Con el ASG corriendo pero sin politica de escalado, la capacidad es fija en 2. La scaling policy define la metrica y el objetivo que disparan el escalado automatico.

### 4.1 Crear Target Tracking Policy (AWS Console)

1. Ir a **EC2 > Auto Scaling Groups > cloudcuyo-api-asg**
2. Pestana **Automatic scaling > Create dynamic scaling policy**
3. Configurar:
   - **Policy type:** `Target tracking scaling`
   - **Scaling policy name:** `cloudcuyo-api-request-tracking`
   - **Metric type:** `Application Load Balancer request count per target`
   - **Target group:** seleccionar `cloudcuyo-api-tg`
   - **Target value:** `100`
   - **Instance warmup:** `60` segundos
4. Click **Create**

> **¿Por que target tracking y no step scaling?** Target tracking funciona como un termostato: le decis "mantene el CPU en 50%" o "mantene 100 requests/target" y AWS calcula automaticamente cuantas instancias lanzar o terminar. Step scaling requiere definir manualmente: "si el CPU esta entre 60% y 80%, agregar 1 instancia; si esta entre 80% y 100%, agregar 2 instancias". Target tracking es mas simple y AWS optimiza la respuesta segun el comportamiento historico de la aplicacion.

> **¿Por que `ALBRequestCountPerTarget` y no CPU?** Para una API que responde en pocos milisegundos, el CPU puede mantenerse bajo incluso con mucho trafico. La metrica de requests por target es mas directa: si el ALB esta enviando mas de 100 requests/minuto a cada instancia, es momento de escalar. En el lab usamos 100 porque es facil de superar con el traffic generator; en produccion el valor dependeria del benchmark real de la aplicacion.

> **¿Que es el Instance Warmup (60s)?** Cuando el ASG lanza una instancia nueva en respuesta a la politica de scaling, esa instancia tarda en arrancar y empezar a recibir trafico. Durante ese tiempo, la metrica puede parecer que sigue alta (pocas instancias activas), lo que podria disparar mas scale-outs innecesarios. El warmup de 60s le dice al ASG "espera este tiempo antes de evaluar de nuevo si necesitas mas instancias".

> **¿Por que 100 requests por target por minuto?** Es un valor intencionalmente bajo para que el scale-out se dispare facilmente en el lab con el traffic generator. En produccion, este valor dependeria del benchmark de la aplicacion (cuantos requests/min puede manejar una instancia antes de que la latencia empiece a degradarse).

### 4.2 Verificar que la politica exista

1. Ir a **EC2 > Auto Scaling Groups > cloudcuyo-api-asg**
2. Pestana **Automatic scaling**
3. Debe aparecer `cloudcuyo-api-request-tracking` de tipo `Target tracking scaling`

---

## Fase 5: Desplegar Traffic Generator

El stack `cloudformation/ha-lab2-traffic-gen.yaml` crea una EC2 en la subnet publica con `ab` (Apache Benchmark) instalado. Genera carga HTTP continua contra el ALB, lo que dispara el scale-out del ASG.

> **¿Por que el traffic generator en una subnet publica?** La EC2 del traffic generator necesita acceso a internet para que el SSM Agent funcione (el agente se comunica con el servicio SSM en internet). Como no tenemos NAT Gateway para subnets privadas, la ponemos en subnet publica con IP publica. El trafico que genera hacia el ALB es interno a la VPC (ALB DNS resuelve a IPs privadas dentro de la red de AWS).

> **¿Por que `ab` (Apache Benchmark) y no un loop de `curl`?** `ab` genera multiples requests concurrentes de forma eficiente y mide el rendimiento. Un loop de `curl` secuencial generaria pocos requests/segundo. Para disparar el scale-out necesitamos superar 100 requests/minuto por target con 30 RPS y 5 workers concurrentes, lo que `ab` maneja facilmente.

### 5.1 Desplegar con CloudFormation (AWS Console)

1. Ir a **CloudFormation > Create stack > With new resources**
2. **Template source:** Upload a template file
3. Seleccionar `cloudformation/ha-lab2-traffic-gen.yaml`
4. Click **Next**
5. **Stack name:** `cloudcuyo-ha-traffic-gen`
6. **Parameters:**
   - **VpcId:** pegar el ID de la VPC
   - **PublicSubnetId:** pegar el ID de la subnet publica AZ-A
   - **ApiSgId:** pegar el ID de `cloudcuyo-api-node-sg` (el SG creado en la Fase 1.2)
   - **SsmInstanceProfile:** pegar `cloudcuyo-ssm-role`
   - **AlbTargetUrl:** `http://<dns-del-alb>` (sin barra final — copiar el DNS name del ALB desde EC2 > Load Balancers)
   - **RequestsPerSecond:** `30`
   - **Workers:** `5`
7. Si la consola muestra algun checkbox de **Capabilities / IAM acknowledgment**, marcarlo. Si no aparece, es normal: este template no crea recursos IAM.
8. Click **Submit**
9. Esperar **CREATE_COMPLETE** (~3 minutos)
10. Ir a la pestana **Outputs** y anotar el Instance ID del traffic generator (columna **Value** de la fila `TrafficGeneratorInstanceId`)

> **Importante:** El servicio `cloudcuyo-load` arranca automaticamente durante el UserData. El trafico empieza pocos minutos despues de crear el stack; no hace falta iniciar nada manualmente para disparar el scale-out.

---

## Fase 6: Observar scale-out bajo carga

### 6.1 Conectarse al traffic generator via SSM

1. Ir a **Systems Manager > Session Manager > Start session**
2. Seleccionar la instancia del traffic generator (Instance ID del output del stack `cloudcuyo-ha-traffic-gen`)
3. Click **Start session**

### 6.2 Verificar que el trafico esta siendo generado

Dentro de la sesion SSM, ejecutar:

```bash
# Ver logs del generador de carga
tail -f /var/log/cloudcuyo-load.log

# Ver si el servicio esta activo
systemctl status cloudcuyo-load --no-pager
```

### 6.3 Observar el scale-out en consola

Abrir estas secciones en el navegador y refrescarlas cada 1-2 minutos:

**EC2 > Auto Scaling Groups > cloudcuyo-api-asg > Activity**

Deberia aparecer un evento similar a:

```
Launching a new EC2 instance: i-xxxxxxxxx
Reason: An instance was started in response to a difference between desired and actual capacity,
increasing the capacity from 2 to 3.
```

**EC2 > Auto Scaling Groups > cloudcuyo-api-asg > Instance management**

Las instancias nuevas apareceran en estado `Pending` → `InService`.

**CloudWatch > Metrics > ApplicationELB:**

- Metrica `RequestCountPerTarget` del Target Group: debe superar 100
- Metrica `HealthyHostCount`: debe aumentar de 2 a 3 o 4

### 6.4 Verificar que el trafico se distribuye entre todas las instancias

1. Abrir el navegador en `http://<DNS-del-ALB>/health`
2. Refrescar varias veces y observar el campo `node` en la respuesta JSON
3. El campo `node` debe mostrar Instance IDs distintos en cada refresh, rotando entre 3 o 4 instancias diferentes a medida que el ASG escala

### Troubleshooting de la Fase 6

| Sintoma | Posible causa | Correccion |
|---|---|---|
| Scale-out no se dispara en 5+ minutos | Metrica RequestCountPerTarget no supera el umbral | Verificar que el traffic generator este activo y que el ALB reciba trafico |
| Traffic generator arranca pero el ALB no recibe requests | URL del ALB incorrecta en el parametro del stack | Verificar parametro `AlbTargetUrl` en CloudFormation > Stacks > cloudcuyo-ha-traffic-gen > Parameters |
| Instancias nuevas del ASG quedan `Unhealthy` | User-data tarda mas de 120s | Esperar, o revisar `/var/log/user-data.log` via SSM en la instancia nueva |
| Scale-out supera el maximo de 4 | No deberia pasar — el maximo esta configurado en 4 | Verificar configuracion del ASG en EC2 > Auto Scaling Groups > cloudcuyo-api-asg > Details |

---

## Fase 7: Detener trafico y observar scale-in

### 7.1 Detener el generador de trafico

Dentro de la sesion SSM en el traffic generator:

```bash
# Detener el servicio de carga
sudo systemctl stop cloudcuyo-load

# Verificar que se detuvo
systemctl status cloudcuyo-load --no-pager
# Debe mostrar "inactive (dead)"

# Confirmar que ya no hay trafico saliente
netstat -an | grep ESTABLISHED | wc -l
```

### 7.2 Observar el scale-in

Despues de detener el trafico, la metrica `RequestCountPerTarget` cae por debajo del umbral. El scale-in de una politica **Target Tracking** es deliberadamente conservador: AWS espera varios datapoints de CloudWatch antes de reducir capacidad para evitar terminar instancias durante una pausa breve de trafico.

> **¿Por que el scale-in tarda mas que el scale-out?** Es intencional. El scale-out debe ser rapido para absorber picos. El scale-in es mas conservador: la alarma baja de target tracking suele evaluar varios minutos de datos antes de actuar. Esto evita terminar instancias que podrian necesitarse si el trafico vuelve a subir.

**Monitorear en consola:** Ir a **EC2 > Auto Scaling Groups > cloudcuyo-api-asg > Activity** y refrescar la pagina cada 30 segundos.

Aparecera un evento similar a:

```
Terminating EC2 instance: i-xxxxxxxxx
Reason: An instance was taken out of service in response to a difference between desired and
actual capacity, decreasing the capacity from 4 to 2.
```

Tambien observar la pestana **Instance management** para ver como las instancias extras pasan a estado `Terminating`.

> **Cuanto tiempo tarda el scale-in?** En este lab puede tardar **15-20 minutos** desde que se detiene el trafico. Es normal ver `Desired=4` durante varios minutos aunque `RequestCountPerTarget` ya haya caido a 0. Cuando la alarma baja pasa a `ALARM`, el ASG reduce primero de 4 a 3 y luego de 3 a 2.

### 7.3 Verificar estado final

1. Ir a **EC2 > Auto Scaling Groups > cloudcuyo-api-asg > Instance management**
2. Debe mostrar exactamente 2 instancias en estado `InService`
3. Ir a **EC2 > Target Groups > cloudcuyo-api-tg > Targets**
4. Debe mostrar exactamente 2 targets en estado `Healthy`

Resultado esperado: `Desired=2`, `InService=2`.

---

## Limpieza

> **El stack `cloudcuyo-ha-traffic-gen` se reutiliza en el Lab HA-03.** Si continuaras con ese lab, no lo elimines.

### Limpieza parcial (conservar ALB, TG y ASG para Lab HA-03)

1. Ir a **CloudFormation > Stacks**
2. Solo eliminar `cloudcuyo-ha-traffic-gen` si NO se continua con Lab HA-03:
   - Seleccionar el stack > **Delete** > confirmar
   - Esperar a que desaparezca de la lista

### Limpieza completa (si no se continua con Lab HA-03)

Eliminar en este orden:

1. **CloudFormation > Stacks** → eliminar `cloudcuyo-ha-traffic-gen` → esperar eliminacion completa
2. **EC2 > Auto Scaling Groups** → seleccionar `cloudcuyo-api-asg` → **Actions > Delete** → escribir `delete` para confirmar → esperar que las instancias terminen (~2-3 minutos)
3. **EC2 > Launch Templates** → seleccionar `cloudcuyo-api-lt` → **Actions > Delete template** → confirmar
4. **EC2 > Load Balancers** → seleccionar `cloudcuyo-api-alb` → **Actions > Delete load balancer** → confirmar → esperar eliminacion
5. **EC2 > Target Groups** → seleccionar `cloudcuyo-api-tg` → **Actions > Delete** → confirmar
6. **EC2 > Security Groups** → eliminar `cloudcuyo-alb-sg` y `cloudcuyo-api-node-sg` → **Actions > Delete security group**

### NO eliminar (pre-requisitos persistentes)

- VPC, subnets, Internet Gateway, route tables
- IAM Role SSM + Instance Profile

---

## Criterios de exito

- El ASG lanza 2 instancias iniciales que quedan `Healthy` en el Target Group
- Al generar carga, el `RequestCountPerTarget` supera 100 y el ASG lanza instancias adicionales (hasta 4)
- Las instancias nuevas del ASG quedan `InService` y reciben trafico del ALB
- Al detener el trafico, el ASG reduce la capacidad de vuelta a 2 instancias despues del periodo conservador de scale-in (~15-20 minutos)
- En ningun momento la API deja de responder durante el scale-out ni el scale-in

---

## Proximo paso

Con el ASG funcionando, la capacidad escala automaticamente. Pero todavia hay un problema: el ASG usa `EC2` health checks por defecto. Si el proceso `gunicorn` se cae sin que la VM se apague, el ASG no lo detecta ni repone la instancia.

**Lab HA-03:** Entender la diferencia entre EC2 y ELB health checks y simular fallas reales de proceso → ver [`guias/guia-ha-03-healthchecks.md`](guia-ha-03-healthchecks.md)
