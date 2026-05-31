# Guia HA-02: Alta Disponibilidad - Auto Scaling Group + Traffic Generator

**Objetivo:** Reemplazar las 2 EC2 fijas del Lab HA-01 por un Auto Scaling Group que ajusta la capacidad automaticamente segun la carga real. Desplegar un generador de trafico via CloudFormation y observar scale-out bajo carga y scale-in al detenerla.

**Duracion estimada:** 2-3 horas

**Estrategia 6R:** **Alta Disponibilidad** — escalado automatico con Auto Scaling Group

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
   | | (EC2 con wrk)    | |  | |                  |  |
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
              |   (mismo del Lab 1)    |
              +-----+------+------+---+
                    |      |      |
                    |      |      |
              +-----+  +---+--+  +-+----+
              |        |      |        |
+------+------+--+  +--+------+--+  +--+------+--+  (hasta 4)
| Private Sub AZ-A |  | Private Sub AZ-A |  | Private Sub AZ-B |
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

**Verificar que el ALB y TG existan:**

```bash
aws elbv2 describe-load-balancers --names cloudcuyo-api-alb \
  --query 'LoadBalancers[0].[LoadBalancerName,State.Code]' \
  --output text

aws elbv2 describe-target-groups --names cloudcuyo-api-tg \
  --query 'TargetGroups[0].[TargetGroupName,TargetType]' \
  --output text
```

Ambos comandos deben devolver resultados sin error. Si alguno falla, volver al Lab HA-01 para recrear los recursos.

**Variables de entorno para este lab:**

**Bash:**

```bash
export VPC_ID=vpc-xxxxxxxxx
export PUBLIC_SUBNET_A_ID=subnet-xxxxxxxxx     # AZ-A
export PUBLIC_SUBNET_B_ID=subnet-xxxxxxxxx     # AZ-B
export PRIVATE_SUBNET_A_ID=subnet-xxxxxxxxx    # AZ-A
export PRIVATE_SUBNET_B_ID=subnet-xxxxxxxxx    # AZ-B
export SSM_INSTANCE_PROFILE=cloudcuyo-ssm-profile

# Obtener ARN del Target Group (necesario para el ASG)
export TG_ARN=$(aws elbv2 describe-target-groups \
  --names cloudcuyo-api-tg \
  --query 'TargetGroups[0].TargetGroupArn' \
  --output text)

# Obtener DNS del ALB
export ALB_DNS=$(aws elbv2 describe-load-balancers \
  --names cloudcuyo-api-alb \
  --query 'LoadBalancers[0].DNSName' \
  --output text)

# Obtener SG de los nodos API (output del stack del Lab 1, o recrear)
export API_NODE_SG_ID=sg-xxxxxxxxx

echo "TG ARN: $TG_ARN"
echo "ALB DNS: $ALB_DNS"
```

**PowerShell:**

```powershell
$VpcId             = "vpc-xxxxxxxxx"
$PublicSubnetAId   = "subnet-xxxxxxxxx"
$PublicSubnetBId   = "subnet-xxxxxxxxx"
$PrivateSubnetAId  = "subnet-xxxxxxxxx"
$PrivateSubnetBId  = "subnet-xxxxxxxxx"
$SsmInstanceProfile = "cloudcuyo-ssm-profile"

$TgArn  = (Get-ELB2TargetGroup -Name "cloudcuyo-api-tg").TargetGroupArn
$AlbDns = (Get-ELB2LoadBalancer -Name "cloudcuyo-api-alb").DNSName
Write-Host "TG ARN: $TgArn"
Write-Host "ALB DNS: $AlbDns"
```

---

## Fase 1: Eliminar los nodos fijos del Lab HA-01

Si el stack `cloudcuyo-ha-lab1-nodes` todavia existe (las 2 EC2 fijas siguen corriendo), se debe eliminar antes de crear el ASG. No es posible tener dos conjuntos de targets en el mismo Target Group con diferente ciclo de vida.

**Verificar si el stack existe:**

```bash
aws cloudformation describe-stacks \
  --stack-name cloudcuyo-ha-lab1-nodes \
  --query 'Stacks[0].StackStatus' \
  --output text 2>/dev/null || echo "Stack no existe"
```

**Si el stack existe, eliminarlo:**

**Bash:**

```bash
aws cloudformation delete-stack --stack-name cloudcuyo-ha-lab1-nodes

echo "Esperando eliminacion..."
aws cloudformation wait stack-delete-complete --stack-name cloudcuyo-ha-lab1-nodes
echo "Nodos fijos eliminados."
```

**PowerShell:**

```powershell
Remove-CFNStack -StackName "cloudcuyo-ha-lab1-nodes" -Force
Wait-CFNStack -StackName "cloudcuyo-ha-lab1-nodes" -Status DELETE_COMPLETE -Timeout 300
Write-Host "Nodos fijos eliminados."
```

**Verificar que el Target Group quede vacio:**

1. Ir a **EC2 > Target Groups > cloudcuyo-api-tg > Targets**
2. Debe aparecer sin targets registrados (o los targets en estado `draining` transitando a `deregistered`)
3. Esperar a que no queden instancias activas antes de continuar

---

## Fase 2: Crear Launch Template

El Launch Template es el "molde" que el ASG usa para lanzar nuevas instancias. Define la AMI, el tipo de instancia, el security group, el IAM profile y el user-data con la instalacion de la API.

### 2.1 Crear Launch Template (AWS Console)

1. Ir a **EC2 > Launch Templates > Create launch template**
2. Configurar seccion **Launch template name and description:**
   - **Launch template name:** `cloudcuyo-api-lt`
   - **Template version description:** `CloudCuyo HA API - v1`
3. Configurar seccion **Application and OS Images (Amazon Machine Image):**
   - Click en **Quick Start**
   - Seleccionar **Amazon Linux**
   - En el selector, elegir **Amazon Linux 2023 AMI** (la mas reciente disponible)
4. Configurar seccion **Instance type:** `t3.micro`
5. Configurar seccion **Key pair (login):** seleccionar `lab-key` (o dejar sin key pair si se usara solo SSM)
6. Configurar seccion **Network settings:**
   - **Firewall (security groups):** seleccionar `cloudcuyo-api-node-sg` (el SG de los nodos del Lab HA-01, o un SG equivalente que permita puerto 5000 desde el ALB)
   - **Auto-assign public IP:** `Disable` (los nodos van en subnets privadas)
7. Configurar seccion **Advanced details:**
   - **IAM instance profile:** seleccionar `cloudcuyo-ssm-profile` (o el nombre del Instance Profile SSM)
   - **User data:** copiar y pegar el siguiente script completo:

```bash
#!/bin/bash
set -e
exec > >(tee /var/log/user-data.log) 2>&1

dnf update -y
dnf install -y python3 python3-pip

INSTANCE_ID=$(curl -s http://169.254.169.254/latest/meta-data/instance-id)
AZ=$(curl -s http://169.254.169.254/latest/meta-data/placement/availability-zone)

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

cat > /etc/systemd/system/cloudcuyo-api.service << SYSTEMD
[Unit]
Description=CloudCuyo HA Demo API
After=network-online.target
[Service]
WorkingDirectory=/opt/cloudcuyo-api
Environment=APP_NODE=$INSTANCE_ID
Environment=APP_AZ=$AZ
ExecStart=/usr/local/bin/gunicorn --bind 0.0.0.0:5000 --workers 2 app:app
Restart=always
RestartSec=3
[Install]
WantedBy=multi-user.target
SYSTEMD

systemctl daemon-reload
systemctl enable cloudcuyo-api
systemctl start cloudcuyo-api
```

8. Click **Create launch template**

> **Por que user-data y no una AMI pre-configurada?** En un ambiente de lab, el user-data permite ver exactamente que se instala sin necesidad de gestionar AMIs personalizadas. En produccion se preferiria una AMI "baked" para reducir el tiempo de arranque de nuevas instancias.

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
   - **Availability Zones and subnets:** seleccionar las dos subnets privadas:
     - `cloudcuyo-private-us-east-1a` (AZ-A)
     - `cloudcuyo-private-us-east-1b` (AZ-B)
   - Click **Next**
4. **Paso 3 - Configure advanced options:**
   - En **Load balancing:**
     - Seleccionar **Attach to an existing load balancer**
     - Seleccionar **Choose from your load balancer target groups**
     - Target group: `cloudcuyo-api-tg`
   - En **Health checks:**
     - **Health check type:** `EC2` (solo EC2 por ahora — se cambia en Lab HA-03)
     - **Health check grace period:** `120` segundos
   - Click **Next**
5. **Paso 4 - Configure group size and scaling:**
   - **Desired capacity:** `2`
   - **Minimum capacity:** `2`
   - **Maximum capacity:** `4`
   - **Automatic scaling:** `No scaling policies` por ahora (se agrega en Fase 4)
   - Click **Next**
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

**Bash — verificar el estado del ASG:**

```bash
aws autoscaling describe-auto-scaling-groups \
  --auto-scaling-group-names cloudcuyo-api-asg \
  --query 'AutoScalingGroups[0].{Desired:DesiredCapacity,Min:MinSize,Max:MaxSize,InService:Instances[?LifecycleState==`InService`]|length(@)}' \
  --output table
```

**PowerShell:**

```powershell
$Asg = Get-ASAutoScalingGroup -AutoScalingGroupName "cloudcuyo-api-asg"
[PSCustomObject]@{
    Desired   = $Asg.DesiredCapacity
    Min       = $Asg.MinSize
    Max       = $Asg.MaxSize
    InService = ($Asg.Instances | Where-Object { $_.LifecycleState -eq "InService" }).Count
} | Format-List
```

### Troubleshooting de la Fase 3

| Sintoma | Posible causa | Correccion |
|---|---|---|
| Instancias no pasan de `Pending` a `InService` | User-data falla o SSM profile incorrecto | Conectarse via SSM y revisar `/var/log/user-data.log` |
| Targets en `Unhealthy` tras el grace period | Puerto 5000 no accesible o API no arranco | Revisar SG y logs de systemd: `journalctl -u cloudcuyo-api` |
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

> **Por que 100 requests por target por minuto?** Es un valor intencialmente bajo para que el scale-out se dispare facilmente en el lab con el traffic generator. En produccion, este valor dependeria del benchmark de la aplicacion (cuantos requests/min puede manejar una instancia antes de que la latencia empiece a degradarse).

### 4.2 Verificar que la politica exista

**Bash:**

```bash
aws autoscaling describe-policies \
  --auto-scaling-group-name cloudcuyo-api-asg \
  --query 'ScalingPolicies[*].[PolicyName,PolicyType,TargetTrackingConfiguration.TargetValue]' \
  --output table
```

**PowerShell:**

```powershell
Get-ASScalingPolicy -AutoScalingGroupName "cloudcuyo-api-asg" |
  Select-Object PolicyName, PolicyType, @{N="TargetValue"; E={$_.TargetTrackingConfiguration.TargetValue}} |
  Format-Table
```

---

## Fase 5: Desplegar Traffic Generator

El stack `cloudformation/ha-lab2-traffic-gen.yaml` crea una EC2 en la subnet publica con `wrk` instalado. Genera carga HTTP continua contra el ALB, lo que dispara el scale-out del ASG.

### 5.1 Desplegar con CloudFormation (AWS Console)

1. Ir a **CloudFormation > Create stack > With new resources**
2. **Template source:** Upload a template file
3. Seleccionar `cloudformation/ha-lab2-traffic-gen.yaml`
4. Click **Next**
5. **Stack name:** `cloudcuyo-ha-traffic-gen`
6. **Parameters:**
   - **VpcId:** pegar `$VPC_ID`
   - **PublicSubnetId:** pegar `$PUBLIC_SUBNET_A_ID`
   - **SsmInstanceProfile:** pegar `$SSM_INSTANCE_PROFILE`
   - **AlbTargetUrl:** `http://<dns-del-alb>` (sin barra final)
   - **RequestsPerSecond:** `30`
   - **Workers:** `5`
7. Marcar **I acknowledge...** > Click **Submit**
8. Esperar **CREATE_COMPLETE** (~3 minutos)
9. Ir a **Outputs** y anotar el Instance ID del traffic generator

**Alternativa CLI:**

**Bash:**

```bash
aws cloudformation create-stack \
  --stack-name cloudcuyo-ha-traffic-gen \
  --template-body file://cloudformation/ha-lab2-traffic-gen.yaml \
  --parameters \
    ParameterKey=VpcId,ParameterValue=$VPC_ID \
    ParameterKey=PublicSubnetId,ParameterValue=$PUBLIC_SUBNET_A_ID \
    ParameterKey=SsmInstanceProfile,ParameterValue=$SSM_INSTANCE_PROFILE \
    ParameterKey=AlbTargetUrl,ParameterValue=http://$ALB_DNS \
    ParameterKey=RequestsPerSecond,ParameterValue=30 \
    ParameterKey=Workers,ParameterValue=5 \
  --capabilities CAPABILITY_NAMED_IAM

aws cloudformation wait stack-create-complete \
  --stack-name cloudcuyo-ha-traffic-gen

TRAFFIC_GEN_ID=$(aws cloudformation describe-stacks \
  --stack-name cloudcuyo-ha-traffic-gen \
  --query 'Stacks[0].Outputs[?OutputKey==`TrafficGenInstanceId`].OutputValue' \
  --output text)

echo "Traffic Generator Instance ID: $TRAFFIC_GEN_ID"
```

**PowerShell:**

```powershell
$TgParams = @(
    @{ ParameterKey = "VpcId";              ParameterValue = $VpcId }
    @{ ParameterKey = "PublicSubnetId";     ParameterValue = $PublicSubnetAId }
    @{ ParameterKey = "SsmInstanceProfile"; ParameterValue = $SsmInstanceProfile }
    @{ ParameterKey = "AlbTargetUrl";       ParameterValue = "http://$AlbDns" }
    @{ ParameterKey = "RequestsPerSecond";  ParameterValue = "30" }
    @{ ParameterKey = "Workers";            ParameterValue = "5" }
)

New-CFNStack -StackName "cloudcuyo-ha-traffic-gen" `
  -TemplateBody (Get-Content "cloudformation\ha-lab2-traffic-gen.yaml" -Raw) `
  -Parameter $TgParams `
  -Capability CAPABILITY_NAMED_IAM

Wait-CFNStack -StackName "cloudcuyo-ha-traffic-gen" -Status CREATE_COMPLETE -Timeout 300

$TrafficGenId = ((Get-CFNStack -StackName "cloudcuyo-ha-traffic-gen").Outputs |
  Where-Object { $_.OutputKey -eq "TrafficGenInstanceId" }).OutputValue
Write-Host "Traffic Generator: $TrafficGenId"
```

---

## Fase 6: Observar scale-out bajo carga

### 6.1 Conectarse al traffic generator via SSM

**AWS Console:**

1. Ir a **Systems Manager > Session Manager > Start session**
2. Seleccionar la instancia del traffic generator
3. Click **Start session**

**Bash:**

```bash
aws ssm start-session --target $TRAFFIC_GEN_ID
```

**PowerShell:**

```powershell
Start-SSMSession -Target $TrafficGenId
```

### 6.2 Verificar que el trafico esta siendo generado

Dentro de la sesion SSM:

```bash
# Ver logs del generador de carga
tail -f /var/log/cloudcuyo-load.log

# Ver si el servicio esta activo
systemctl status cloudcuyo-load --no-pager

# Ver el rate actual de requests
curl -s http://localhost:9091/metrics 2>/dev/null | grep requests || \
  echo "Metricas locales no disponibles, ver logs"
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

**Bash — monitorear el conteo de instancias cada 30 segundos:**

```bash
while true; do
  COUNT=$(aws autoscaling describe-auto-scaling-groups \
    --auto-scaling-group-names cloudcuyo-api-asg \
    --query 'AutoScalingGroups[0].Instances[?LifecycleState==`InService`] | length(@)' \
    --output text)
  echo "$(date +%H:%M:%S) InService instances: $COUNT"
  sleep 30
done
```

### 6.4 Verificar que el trafico se distribuye entre todas las instancias

```bash
# Desde la terminal local (no desde SSM):
ALB_DNS=<dns-del-alb>

for i in $(seq 1 20); do
  curl -s http://$ALB_DNS/health | python3 -c \
    "import sys,json; d=json.load(sys.stdin); print(f'{d[\"node\"][:12]}... {d[\"az\"]}')"
done | sort | uniq -c | sort -rn
```

El conteo deberia mostrar requests distribuidos entre 3 o 4 Instance IDs distintos.

### Troubleshooting de la Fase 6

| Sintoma | Posible causa | Correccion |
|---|---|---|
| Scale-out no se dispara en 5+ minutos | Metrica RequestCountPerTarget no supera el umbral | Verificar que el traffic generator este activo y que el ALB reciba trafico |
| Traffic generator arranca pero el ALB no recibe requests | URL del ALB incorrecta en el parametro del stack | Verificar parametro `AlbTargetUrl` en stack outputs |
| Instancias nuevas del ASG quedan `Unhealthy` | User-data tarda mas de 120s | Esperar, o revisar `/var/log/user-data.log` via SSM en la instancia nueva |
| Scale-out supera el maximo de 4 | No deberia pasar — el maximo esta configurado en 4 | Verificar configuracion del ASG |

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

Despues de detener el trafico, la metrica `RequestCountPerTarget` cae por debajo del umbral de 100. El ASG espera el **scale-in cooldown** (configurado en 120 segundos) antes de terminar instancias.

**En consola:** EC2 > Auto Scaling Groups > cloudcuyo-api-asg > Activity

Aparecera un evento similar a:

```
Terminating EC2 instance: i-xxxxxxxxx
Reason: An instance was taken out of service in response to a difference between desired and
actual capacity, decreasing the capacity from 4 to 2.
```

**Bash — monitorear hasta que vuelva a 2 instancias:**

```bash
while true; do
  COUNT=$(aws autoscaling describe-auto-scaling-groups \
    --auto-scaling-group-names cloudcuyo-api-asg \
    --query 'AutoScalingGroups[0].Instances[?LifecycleState==`InService`] | length(@)' \
    --output text)
  echo "$(date +%H:%M:%S) InService instances: $COUNT"
  [ "$COUNT" -le "2" ] && echo "Scale-in completado." && break
  sleep 30
done
```

> **Cuanto tiempo tarda el scale-in?** Con cooldown de 120 segundos, la metrica debe estar por debajo del umbral durante todo ese periodo antes de que el ASG actue. Tipicamente el scale-in completo toma 3-5 minutos desde que se detiene el trafico.

### 7.3 Verificar estado final

```bash
aws autoscaling describe-auto-scaling-groups \
  --auto-scaling-group-names cloudcuyo-api-asg \
  --query 'AutoScalingGroups[0].{Desired:DesiredCapacity,Min:MinSize,Max:MaxSize,InService:Instances[?LifecycleState==`InService`]|length(@)}' \
  --output table
```

Resultado esperado: `Desired=2, InService=2`.

---

## Limpieza

> **El stack `cloudcuyo-ha-traffic-gen` se reutiliza en el Lab HA-03.** Si continuaras con ese lab, no lo elimines.

### Limpieza parcial (conservar ALB, TG y ASG para Lab HA-03)

```bash
# Solo eliminar el traffic generator si NO se continua con Lab HA-03
aws cloudformation delete-stack --stack-name cloudcuyo-ha-traffic-gen
```

### Limpieza completa (si no se continua con Lab HA-03)

**Bash:**

```bash
# 1. Eliminar traffic generator
aws cloudformation delete-stack --stack-name cloudcuyo-ha-traffic-gen
aws cloudformation wait stack-delete-complete --stack-name cloudcuyo-ha-traffic-gen

# El ASG, Launch Template, ALB y TG se eliminan desde consola:
# 2. EC2 > Auto Scaling Groups > cloudcuyo-api-asg > Delete
# 3. EC2 > Launch Templates > cloudcuyo-api-lt > Actions > Delete
# 4. EC2 > Load Balancers > cloudcuyo-api-alb > Actions > Delete
# 5. EC2 > Target Groups > cloudcuyo-api-tg > Actions > Delete
# 6. EC2 > Security Groups > cloudcuyo-alb-sg y cloudcuyo-api-node-sg > Delete
```

**PowerShell:**

```powershell
Remove-CFNStack -StackName "cloudcuyo-ha-traffic-gen" -Force
Wait-CFNStack  -StackName "cloudcuyo-ha-traffic-gen" -Status DELETE_COMPLETE -Timeout 300
Write-Host "Traffic generator eliminado. Completar limpieza de ASG, LT, ALB y TG desde consola."
```

### NO eliminar (pre-requisitos persistentes)

- VPC, subnets, Internet Gateway, route tables
- IAM Role SSM + Instance Profile
- Stack `cloudcuyo-nat` si existe

---

## Criterios de exito

- El ASG lanza 2 instancias iniciales que quedan `Healthy` en el Target Group
- Al generar carga, el `RequestCountPerTarget` supera 100 y el ASG lanza instancias adicionales (hasta 4)
- Las instancias nuevas del ASG quedan `InService` y reciben trafico del ALB
- Al detener el trafico, el ASG reduce la capacidad de vuelta a 2 instancias en ~3-5 minutos
- En ningun momento la API deja de responder durante el scale-out ni el scale-in

---

## Proximo paso

Con el ASG funcionando, la capacidad escala automaticamente. Pero todavia hay un problema: el ASG usa `EC2` health checks por defecto. Si el proceso `gunicorn` se cae sin que la VM se apague, el ASG no lo detecta ni repone la instancia.

**Lab HA-03:** Entender la diferencia entre EC2 y ELB health checks y simular fallas reales de proceso → ver [`guias/guia-ha-03-healthchecks.md`](guia-ha-03-healthchecks.md)
