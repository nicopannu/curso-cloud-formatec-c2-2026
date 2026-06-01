# Guia HA-01: Alta Disponibilidad - ALB + 2 instancias EC2

**Objetivo:** Reemplazar el NGINX `lb01` (punto unico de falla) por un Application Load Balancer administrado con dos instancias de API distribuidas en dos Availability Zones. El alumno observa distribucion de trafico, health checks automaticos y failover basico.

**Duracion estimada:** 1.5-2 horas

**Módulo:** Módulo 2 — Clase 2: Alta Disponibilidad

---

## Contexto

CloudCuyo tiene la API corriendo en una sola instancia `api01`. Funciona, pero tiene un problema arquitectonico critico: `api01` es un **punto unico de falla (SPOF)**. Si esa instancia se cae, toda la API queda inaccesible. Los clientes que usan los endpoints `/api/v1/*` para sus sistemas de monitoreo y facturacion pierden conectividad sin previo aviso.

El `lb01` heredado del on-premise tampoco ayuda: es otra instancia EC2 que puede fallar, y distribuye trafico solo entre los frontends estaticos, no entre multiples instancias de API.

En este lab se reemplaza ese esquema fragil por un **Application Load Balancer administrado por AWS** con dos nodos de API en Availability Zones distintas. Si un nodo falla, el ALB detecta la falla automaticamente via health checks y deja de enviarle trafico, sin interrupcion perceptible para los usuarios.

**Por que ALB y no seguir con NGINX en EC2:**

- AWS administra la disponibilidad del balanceador mismo (no hay SPOF en el LB)
- Health checks automaticos con configurable de umbrales
- Integration nativa con Auto Scaling (base para el Lab HA-02)
- Sin necesidad de mantener, parchear ni monitorear el proceso NGINX del lb01

---

## Arquitectura objetivo

```
                         Internet
                            |
                           IGW
                            |
              +-------------+-------------+
              |                           |
   +-----------+----------+  +-----------+----------+
   | Public Subnet AZ-A   |  | Public Subnet AZ-B   |
   | (10.0.0.0/24)        |  | (10.0.2.0/24)        |
   |                      |  |                      |
   |   +----------------+ |  | +----------------+   |
   |   |                | |  | |                |   |
   |   |   ALB node     | |  | |   ALB node     |   |
   |   | (administrado) | |  | | (administrado) |   |
   |   +-------+--------+ |  | +--------+-------+   |
   +-----------|----------+  +----------|------------+
               |                        |
               +----------+-------------+
                          |
               +----------+-------------+
               |    Target Group        |
               |   (HTTP:5000 /health)  |
               +-------+--------+------+
                       |        |
        +--------------+        +--------------+
        |                                      |
+-------+------------------+    +--------------+--------+
| Public Subnet AZ-A       |    | Public Subnet AZ-B    |
| (10.0.0.0/24)            |    | (10.0.2.0/24)         |
|                          |    |                       |
|  +-------------------+   |    |  +-------------------+|
|  | api-node-1        |   |    |  | api-node-2        ||
|  | Flask + Gunicorn  |   |    |  | Flask + Gunicorn  ||
|  | :5000             |   |    |  | :5000             ||
|  +-------------------+   |    |  +-------------------+|
+--------------------------+    +-----------------------+
```

---

## Pre-requisitos

### Herramientas y acceso

- Acceder a [https://console.aws.amazon.com/](https://console.aws.amazon.com/)
- Region: **us-east-1 (N. Virginia)**
- Permisos para EC2, VPC, CloudFormation e IAM

**Bash (Linux/Mac/WSL):**

```bash
aws --version       # AWS CLI >= 2.x
aws sts get-caller-identity
```

**PowerShell (Windows):**

```powershell
Get-STSCallerIdentity
```

### Recursos de red necesarios

Este lab requiere dos Availability Zones completas (public + private cada una). La VPC del lab ya tiene subnets en AZ-A. La AZ-B se crea como parte de los pre-requisitos de este lab.

**Recursos requeridos antes de comenzar las Fases:**

| Recurso | Descripcion | Estado |
|---|---|---|
| VPC `10.0.0.0/16` con IGW | Pre-existente en la cuenta | Debe existir |
| Public Subnet AZ-A (`10.0.0.0/24`) | Pre-existente, asociada a RTB publica | Debe existir |
| Private Subnet AZ-A (`10.0.1.0/24`) | Pre-existente, asociada a RTB privada | Debe existir |
| Public Subnet AZ-B (`10.0.2.0/24`) | **Crear en este pre-req** | A crear |
| Private Subnet AZ-B (`10.0.3.0/24`) | **Crear en este pre-req** | A crear |
| IAM Role SSM + Instance Profile | **Crear si no existe** | A verificar/crear |

---

### Pre-req A: Crear Public Subnet AZ-B (`10.0.2.0/24`)

> **¿Por que necesitamos una segunda AZ?** Un ALB necesita estar en al menos dos Availability Zones para ser altamente disponible. Una AZ es un datacenter fisicamente separado dentro de la region. Si todo esta en una sola AZ y esa falla, el ALB tambien cae. Distribuir en dos AZs significa que una puede fallar sin afectar el servicio.

**Usando AWS Console:**

1. Ir a **VPC > Subnets**
2. Click en **Create subnet**
3. Seleccionar la VPC del laboratorio
4. Configurar:
   - **Subnet name:** `cloudcuyo-public-us-east-1b`
   - **Availability Zone:** `us-east-1b`
   - **IPv4 CIDR block:** `10.0.2.0/24`
5. Click en **Create subnet**
6. Seleccionar la nueva subnet > **Actions > Edit subnet settings**
7. Marcar **Enable auto-assign public IPv4 address** > Guardar
8. Ir a **VPC > Route tables**
9. Seleccionar la **route table publica** (la que tiene ruta `0.0.0.0/0 → igw-xxxxx`)
10. Ir a pestana **Subnet associations > Edit subnet associations**
11. Agregar la nueva subnet `cloudcuyo-public-us-east-1b` > Guardar

> **¿Por que asociar la subnet a la route table publica?** Una subnet "publica" es simplemente una subnet cuya route table tiene una ruta `0.0.0.0/0 → IGW`. Sin esa ruta, el trafico de internet no llega. Asociar la nueva subnet a la misma route table publica garantiza que el ALB pueda recibir trafico externo desde ambas AZs.

**Alternativa CLI:**

```bash
# Crear subnet publica AZ-B
PUBLIC_SUBNET_B_ID=$(aws ec2 create-subnet \
  --vpc-id $VPC_ID \
  --cidr-block 10.0.2.0/24 \
  --availability-zone us-east-1b \
  --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=cloudcuyo-public-us-east-1b}]' \
  --query 'Subnet.SubnetId' \
  --output text)

echo "Public Subnet B: $PUBLIC_SUBNET_B_ID"

# Activar auto-assign public IP
aws ec2 modify-subnet-attribute \
  --subnet-id $PUBLIC_SUBNET_B_ID \
  --map-public-ip-on-launch

# Asociar a la route table publica (reemplazar $PUBLIC_RT_ID con el ID real)
aws ec2 associate-route-table \
  --subnet-id $PUBLIC_SUBNET_B_ID \
  --route-table-id $PUBLIC_RT_ID
```

---

### Pre-req B: Crear Private Subnet AZ-B (`10.0.3.0/24`)

> **¿Por que creamos la subnet privada si los nodos van en publicas?** La subnet privada AZ-B es un pre-requisito para labs futuros (HA-02 y HA-03) y para contar con la estructura de red correcta (cada AZ deberia tener una subnet publica y una privada). No la usamos en este lab pero la creamos ahora para no tener que interrumpir el flujo despues.

**Usando AWS Console:**

1. Ir a **VPC > Subnets > Create subnet**
2. Seleccionar la misma VPC
3. Configurar:
   - **Subnet name:** `cloudcuyo-private-us-east-1b`
   - **Availability Zone:** `us-east-1b`
   - **IPv4 CIDR block:** `10.0.3.0/24`
4. Click en **Create subnet**
5. Ir a **VPC > Route tables**
6. Seleccionar la **route table privada** (la que tiene ruta `0.0.0.0/0 → nat-xxxxx` o la instancia NAT)
7. Ir a pestana **Subnet associations > Edit subnet associations**
8. Agregar la nueva subnet `cloudcuyo-private-us-east-1b` > Guardar

**Alternativa CLI:**

```bash
# Crear subnet privada AZ-B
PRIVATE_SUBNET_B_ID=$(aws ec2 create-subnet \
  --vpc-id $VPC_ID \
  --cidr-block 10.0.3.0/24 \
  --availability-zone us-east-1b \
  --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=cloudcuyo-private-us-east-1b}]' \
  --query 'Subnet.SubnetId' \
  --output text)

echo "Private Subnet B: $PRIVATE_SUBNET_B_ID"

# Asociar a la route table privada (reemplazar $PRIVATE_RT_ID con el ID real)
aws ec2 associate-route-table \
  --subnet-id $PRIVATE_SUBNET_B_ID \
  --route-table-id $PRIVATE_RT_ID
```

---

### Pre-req C: Verificar o crear IAM Role SSM

> **¿Por que necesitan las EC2 un IAM Role?** Por defecto, una instancia EC2 no tiene permisos para interactuar con otros servicios de AWS. El IAM Role actua como una "identidad" que se asigna a la instancia y le otorga permisos especificos. En este caso, `AmazonSSMManagedInstanceCore` permite al SSM Agent de la instancia comunicarse con el servicio Systems Manager sin necesidad de una clave SSH ni una IP publica accesible. Esto es mas seguro y operativamente mas simple que gestionar claves SSH.

Si ya existe un Instance Profile SSM en la cuenta, obtener su nombre con:

```bash
aws iam list-instance-profiles \
  --query 'InstanceProfiles[*].InstanceProfileName' \
  --output table
```

**Si no existe, crearlo manualmente:**

**Usando AWS Console:**

1. Ir a **IAM > Roles > Create role**
2. **Trusted entity type:** AWS service
3. **Use case:** EC2
4. **Permissions:** agregar `AmazonSSMManagedInstanceCore`
5. **Role name:** `cloudcuyo-ssm-role`
6. Click **Create role**
7. Ir a **IAM > Instance profiles** (en la URL: `/iam/home#/instanceProfiles`)
8. Si el Instance Profile no se creo automaticamente con el rol, usar CLI:

```bash
aws iam create-instance-profile --instance-profile-name cloudcuyo-ssm-profile
aws iam add-role-to-instance-profile \
  --instance-profile-name cloudcuyo-ssm-profile \
  --role-name cloudcuyo-ssm-role
```

---

### Variables de entorno para el lab

Completar y exportar antes de empezar las Fases:

```bash
export VPC_ID=vpc-xxxxxxxxx
export PUBLIC_SUBNET_A_ID=subnet-xxxxxxxxx   # AZ-A, ya existe
export PUBLIC_SUBNET_B_ID=subnet-xxxxxxxxx   # AZ-B, recien creada
export SSM_INSTANCE_PROFILE=cloudcuyo-ssm-profile   
```

---

## Fase 1: Crear Security Group del ALB

El Security Group del ALB se crea **primero** porque los nodos API necesitan su ID para restringir el trafico: solo aceptan conexiones desde el ALB, no desde Internet directamente.

> **¿Por que crear el SG del ALB ANTES de desplegar el stack?** El stack de CloudFormation necesita el ID del SG del ALB como parametro porque lo usa para configurar el SG de los nodos API: las instancias solo aceptan trafico en puerto 5000 desde el SG del ALB. Si el ALB SG no existe, el stack no se puede desplegar.

> **¿Por que un Security Group separado para el ALB y otro para los nodos?** Es el patron estandar de seguridad en AWS. El ALB SG acepta trafico publico (port 80 desde `0.0.0.0/0`). El SG de los nodos solo acepta trafico desde el SG del ALB. Esto garantiza que ningun usuario pueda llegar directamente a los nodos de API, solo a traves del balanceador. Incluso si los nodos tienen IP publica (como en este lab), el SG los protege.

### 1.1 Crear SG del ALB (AWS Console)

1. Ir a **EC2 > Security Groups > Create security group**
2. Configurar:
   - **Security group name:** `cloudcuyo-alb-sg`
   - **Description:** `CloudCuyo ALB - allow HTTP from Internet`
   - **VPC:** seleccionar la VPC del lab
3. En **Inbound rules > Add rule:**
   - **Type:** HTTP
   - **Source:** `0.0.0.0/0`
4. Click **Create security group**
5. Anotar el **Security Group ID** (formato `sg-xxxxxxxxx`)

**Alternativa CLI:**

```bash
ALB_SG_ID=$(aws ec2 create-security-group \
  --group-name cloudcuyo-alb-sg \
  --description "CloudCuyo ALB - allow HTTP from Internet" \
  --vpc-id $VPC_ID \
  --query 'GroupId' \
  --output text)

aws ec2 authorize-security-group-ingress \
  --group-id $ALB_SG_ID \
  --protocol tcp \
  --port 80 \
  --cidr 0.0.0.0/0

echo "ALB SG ID: $ALB_SG_ID"
```

---

## Fase 2: Desplegar nodos API con CloudFormation

> **¿Que crea el stack?** El stack despliega dos instancias EC2 con Amazon Linux 2023. Cada instancia ejecuta un script de bootstrap (UserData) que instala Python, Flask y Gunicorn, luego arranca la API como un servicio systemd. El campo `node` en las respuestas de la API se obtiene del Instance Metadata Service (IMDS) de AWS al momento de arrancar, por eso cada nodo responde con su propio Instance ID.

> **¿Por que subnets publicas y no privadas?** Las instancias necesitan acceso a internet durante el bootstrap para descargar paquetes (`dnf update`, `pip3 install flask gunicorn`). Sin un NAT Gateway en la VPC, las instancias en subnets privadas no tienen salida a internet y el bootstrap falla silenciosamente. Aunque las instancias tienen IP publica, el SG las protege: solo el ALB puede llegar al puerto 5000. En un entorno de produccion con NAT Gateway, los nodos irian en subnets privadas.

El stack `cloudformation/ha-lab1-nodes.yaml` crea las dos instancias EC2 con la API Flask corriendo en puerto 5000, distribuidas en AZ-A y AZ-B. El SG de los nodos solo permite trafico desde el SG del ALB creado en la Fase 1.

### 2.1 Desplegar con CloudFormation (AWS Console)

1. Ir a **CloudFormation > Create stack > With new resources (standard)**
2. **Template source:** Upload a template file
3. Seleccionar `cloudformation/ha-lab1-nodes.yaml` del repositorio
4. Click **Next**
5. **Stack name:** `cloudcuyo-ha-lab1-nodes`
6. **Parameters:**
   - **VpcId:** pegar `$VPC_ID`
   - **SubnetAId:** pegar `$PUBLIC_SUBNET_A_ID`
   - **SubnetBId:** pegar `$PUBLIC_SUBNET_B_ID`
   - **AlbSgId:** pegar `$ALB_SG_ID` (del paso anterior)
   - **SsmInstanceProfile:** pegar `$SSM_INSTANCE_PROFILE`
7. Click **Next** dos veces
8. Marcar **I acknowledge that AWS CloudFormation might create IAM resources with custom names**
9. Click **Submit**
10. Esperar a estado **CREATE_COMPLETE** (~3-5 minutos)
11. Ir a pestana **Outputs** y anotar:
    - **ApiNode1PrivateIp:** IP privada del nodo 1 (AZ-A)
    - **ApiNode2PrivateIp:** IP privada del nodo 2 (AZ-B)
    - **ApiNode1InstanceId:** Instance ID del nodo 1
    - **ApiNode2InstanceId:** Instance ID del nodo 2
    - **ApiNodeSgId:** Security Group ID de los nodos (se reutiliza en Lab HA-02)

**Alternativa CLI:**

```bash
aws cloudformation create-stack \
  --stack-name cloudcuyo-ha-lab1-nodes \
  --template-body file://cloudformation/ha-lab1-nodes.yaml \
  --parameters \
    ParameterKey=VpcId,ParameterValue=$VPC_ID \
    ParameterKey=SubnetAId,ParameterValue=$PUBLIC_SUBNET_A_ID \
    ParameterKey=SubnetBId,ParameterValue=$PUBLIC_SUBNET_B_ID \
    ParameterKey=AlbSgId,ParameterValue=$ALB_SG_ID \
    ParameterKey=SsmInstanceProfile,ParameterValue=$SSM_INSTANCE_PROFILE \
  --capabilities CAPABILITY_NAMED_IAM

echo "Esperando a que se complete el stack..."
aws cloudformation wait stack-create-complete \
  --stack-name cloudcuyo-ha-lab1-nodes

echo "Outputs del stack:"
aws cloudformation describe-stacks \
  --stack-name cloudcuyo-ha-lab1-nodes \
  --query 'Stacks[0].Outputs' \
  --output table
```

### 2.2 Verificar que los nodos esten corriendo

```bash
# Exportar IPs de los outputs
NODE1_IP=$(aws cloudformation describe-stacks \
  --stack-name cloudcuyo-ha-lab1-nodes \
  --query 'Stacks[0].Outputs[?OutputKey==`ApiNode1PrivateIp`].OutputValue' \
  --output text)

NODE2_IP=$(aws cloudformation describe-stacks \
  --stack-name cloudcuyo-ha-lab1-nodes \
  --query 'Stacks[0].Outputs[?OutputKey==`ApiNode2PrivateIp`].OutputValue' \
  --output text)

API_NODE_SG_ID=$(aws cloudformation describe-stacks \
  --stack-name cloudcuyo-ha-lab1-nodes \
  --query 'Stacks[0].Outputs[?OutputKey==`ApiNodeSgId`].OutputValue' \
  --output text)

echo "Nodo 1: $NODE1_IP"
echo "Nodo 2: $NODE2_IP"
echo "API Node SG: $API_NODE_SG_ID"
```

> **Nota:** Las instancias recien lanzadas pueden tardar 1-2 minutos en inicializar la API via user-data. Si se intenta registrarlas en el Target Group de inmediato, pueden aparecer en estado `Initial`. Eso es normal.

### Troubleshooting de la Fase 2

| Sintoma | Posible causa | Correccion |
|---|---|---|
| Stack queda en `CREATE_FAILED` | Parametro incorrecto (subnet ID, SG ID) | Revisar eventos del stack en CloudFormation > Events |
| Stack falla con error IAM | `--capabilities CAPABILITY_NAMED_IAM` no incluido | Agregar el flag en CLI o marcar checkbox en consola |
| Instancias en estado `running` pero API no responde | User-data aun ejecutando | Esperar 2-3 minutos, luego verificar via SSM |

---

## Fase 3: Crear Target Group

El Target Group es el componente que le dice al ALB a que instancias enviar trafico y como verificar su salud.

> **¿Que es un Target Group?** Un Target Group es la "lista de destinos" del ALB. El ALB no habla directamente con las instancias: habla con un Target Group, y el Target Group sabe a cuales instancias enviar el trafico. Esta separacion permite que el ALB tenga multiples Target Groups (para diferentes rutas o aplicaciones) y que el Target Group pueda cambiar sus miembros (como hace el ASG en Lab HA-02) sin modificar el ALB.

### 3.1 Crear Target Group (AWS Console)

1. Ir a **EC2 > Target Groups > Create target group**
2. **Target type:** Instances
3. Configurar:
   - **Target group name:** `cloudcuyo-api-tg`
   - **Protocol:** HTTP
   - **Port:** `5000`
   - **VPC:** seleccionar la VPC del lab
4. En **Health checks:**
   - **Protocol:** HTTP
   - **Health check path:** `/health`
   - Expandir **Advanced health check settings:**
     - **Healthy threshold:** `2`
     - **Unhealthy threshold:** `2`
     - **Timeout:** `5` segundos
     - **Interval:** `15` segundos
5. Click **Next**
6. En **Register targets:**
   - Seleccionar las dos instancias del stack `cloudcuyo-ha-lab1-nodes`
   - Verificar que el puerto sea `5000`
   - Click **Include as pending below**
7. Click **Create target group**
8. Anotar el **ARN del Target Group** (se reutiliza en Lab HA-02)

> **¿Por que el protocolo HTTP y el puerto 5000?** La API Flask corre detras de Gunicorn en el puerto 5000. El ALB se comunica con los nodos en ese puerto. El trafico externo llega al ALB en el puerto 80 (HTTP), y el ALB lo reenvía internamente a los nodos en el puerto 5000. El Target Group define ese reenvio interno.

> **¿Por que el health check path es `/health`?** El ALB necesita un endpoint que le diga si la instancia esta sana. `/health` es un endpoint de la API que devuelve `{"status": "ok"}` con codigo HTTP 200 cuando la API esta funcionando. El ALB hace GET a ese path cada 15 segundos. Si recibe 200, el target esta Healthy. Si no recibe respuesta o recibe un error, el target esta Unhealthy.

> **¿Que significan los umbrales 2/2 con intervalo 15s?** Umbral healthy=2 significa que se necesitan 2 checks consecutivos exitosos para marcar un target como Healthy. Umbral unhealthy=2 significa 2 checks fallidos consecutivos para marcarlo como Unhealthy. Con intervalo de 15s, el ALB tarda ~30s en detectar que un nodo caido esta Unhealthy y dejar de enviarle trafico. Un umbral mas bajo reacciona mas rapido pero es mas susceptible a falsos positivos.

### Troubleshooting de la Fase 3

| Sintoma | Posible causa | Correccion |
|---|---|---|
| Targets quedan en `Unhealthy` al registrar | API aun iniciando o SG incorrecto | Esperar 2 min y revisar que el SG del ALB este correctamente referenciado en el SG de los nodos |
| Targets quedan en `Initial` por mucho tiempo | Health check interval alto o grace period | Normal en instancias recien lanzadas; esperar primer ciclo de health checks |
| Error "port 5000 not reachable" | SG de los nodos no permite trafico desde SG del ALB | Verificar la regla inbound del SG de los nodos |

---

## Fase 4: Crear Application Load Balancer

### 4.1 Crear ALB (AWS Console)

1. Ir a **EC2 > Load Balancers > Create load balancer**
2. Seleccionar **Application Load Balancer > Create**
3. Configurar:
   - **Load balancer name:** `cloudcuyo-api-alb`
   - **Scheme:** `Internet-facing`
   - **IP address type:** `IPv4`
4. En **Network mapping:**
   - **VPC:** seleccionar la VPC del lab
   - **Mappings:** marcar las dos AZs y seleccionar las public subnets:
     - `us-east-1a` → subnet publica AZ-A
     - `us-east-1b` → `cloudcuyo-public-us-east-1b` (recien creada)
5. En **Security groups:**
   - Quitar el SG default
   - Agregar `cloudcuyo-alb-sg`
6. En **Listeners and routing:**
   - **Protocol:** HTTP, **Port:** 80
   - **Default action:** Forward to `cloudcuyo-api-tg`
7. Click **Create load balancer**
8. Esperar a que el estado sea **Active** (~2-3 minutos)
9. Copiar el **DNS name** del ALB (ejemplo: `cloudcuyo-api-alb-123456789.us-east-1.elb.amazonaws.com`)

> **¿Que es "internet-facing"?** Un ALB internet-facing tiene IPs publicas y puede recibir trafico desde internet. La alternativa es "internal", que solo acepta trafico desde dentro de la VPC (util para microservicios que se comunican entre si). Para CloudCuyo, la API es publica, asi que necesitamos internet-facing.

> **¿Por que el ALB necesita estar en AMBAS subnets publicas?** El ALB distribuye el trafico entre AZs. Para hacer eso, necesita un nodo propio en cada AZ. Al seleccionar las dos subnets publicas (AZ-A y AZ-B), AWS despliega el ALB en ambas zonas. Si una AZ falla, el nodo del ALB en la AZ sana sigue operando.

```bash
# Obtener DNS del ALB una vez creado
ALB_DNS=$(aws elbv2 describe-load-balancers \
  --names cloudcuyo-api-alb \
  --query 'LoadBalancers[0].DNSName' \
  --output text)

echo "ALB DNS: $ALB_DNS"
```

### Troubleshooting de la Fase 4

| Sintoma | Posible causa | Correccion |
|---|---|---|
| Error "Subnet must be in two different AZs" | Se selecciono la misma AZ dos veces o una sola subnet | Asegurarse de marcar `us-east-1a` y `us-east-1b` con subnets distintas |
| ALB queda en estado `Provisioning` por mas de 10 min | Problema de red o cuota | Revisar eventos del ALB en CloudWatch o contactar al instructor |
| DNS del ALB no resuelve aun | DNS propagation | Esperar 1-2 minutos antes de intentar curl |

---

## Fase 5: Validar distribucion de trafico

Una vez que el ALB esta Active y los dos targets estan Healthy, comprobar que el trafico se distribuye entre ambos nodos.

### 5.1 Verificar estado de los targets

**AWS Console:**

1. Ir a **EC2 > Target Groups > cloudcuyo-api-tg**
2. Pestana **Targets**
3. Ambas instancias deben estar en estado **Healthy**

```bash
# Verificar estado de los targets
aws elbv2 describe-target-health \
  --target-group-arn $(aws elbv2 describe-target-groups \
    --names cloudcuyo-api-tg \
    --query 'TargetGroups[0].TargetGroupArn' \
    --output text) \
  --query 'TargetHealthDescriptions[*].[Target.Id,TargetHealth.State]' \
  --output table
```

### 5.2 Probar distribucion round-robin

```bash
export ALB_DNS=<dns-del-alb>

# Repetir 10 veces y observar que el campo "node" alterna entre instancias
for i in $(seq 1 10); do
  echo "Request $i:"
  curl -s http://$ALB_DNS/health | python3 -m json.tool
  sleep 1
done
```

Respuesta esperada (el campo `node` debe alternar entre los dos Instance IDs):

```json
{
    "node": "i-0a1b2c3d4e5f67890",
    "az": "us-east-1a",
    "status": "ok"
}
```

```json
{
    "node": "i-0f9e8d7c6b5a43210",
    "az": "us-east-1b",
    "status": "ok"
}
```

> **¿Por que el campo `node` alterna?** El ALB usa round-robin por defecto: cada request va a una instancia diferente en orden rotatorio. El campo `node` contiene el Instance ID de la EC2 que respondio (obtenido del IMDS al arrancar). Ver que alterna entre dos Instance IDs distintos confirma que el ALB esta distribuyendo el trafico y que ambos nodos estan procesando requests.

---

## Fase 6: Simular falla de un nodo y observar failover

Este experimento ilustra la ventaja clave del ALB sobre un servidor unico: cuando un nodo falla, el ALB detecta la falla via health checks y deja de enviarle trafico automaticamente.

### 6.1 Terminar uno de los nodos

**AWS Console:**

1. Ir a **EC2 > Instances**
2. Seleccionar `cloudcuyo-api-node-1` (o el nodo en AZ-A)
3. **Instance state > Terminate instance > Terminate**

> **¿Que diferencia hay entre Stop y Terminate?** Stop apaga la VM pero la conserva (como "hibernar"). Terminate la destruye permanentemente. Para simular una falla real (crash de hardware, falla de zona), usamos Terminate. El ALB detecta la falla cuando los health checks fallan —no cuando la instancia se termina— asi que el comportamiento es el mismo en ambos casos.

### 6.2 Observar el comportamiento del ALB

Abrir las siguientes ventanas en paralelo para observar en tiempo real:

**Ventana 1 - Curl en loop:**

```bash
while true; do
  echo -n "$(date +%H:%M:%S) "
  curl -s --max-time 3 http://$ALB_DNS/health | python3 -c "import sys,json; d=json.load(sys.stdin); print(f'node={d[\"node\"][:12]}... az={d[\"az\"]}')" 2>/dev/null || echo "TIMEOUT"
  sleep 2
done
```

**Ventana 2 - Estado del Target Group:**

**En AWS Console:** EC2 > Target Groups > cloudcuyo-api-tg > Targets (refrescar manualmente cada 15s)

O via CLI:

```bash
TG_ARN=$(aws elbv2 describe-target-groups \
  --names cloudcuyo-api-tg \
  --query 'TargetGroups[0].TargetGroupArn' \
  --output text)

watch -n 10 "aws elbv2 describe-target-health \
  --target-group-arn $TG_ARN \
  --query 'TargetHealthDescriptions[*].[Target.Id,TargetHealth.State,TargetHealth.Reason]' \
  --output table"
```

### 6.3 Secuencia esperada de eventos

| Tiempo | Que sucede |
|---|---|
| T+0s | Instancia termina |
| T+15-30s | ALB health check falla (primer check) |
| T+30-45s | ALB marca el target como `Unhealthy` (umbral=2 checks fallidos) |
| T+45s+ | ALB solo envia trafico al nodo sano |
| Loop curl | `node` muestra solo el ID del nodo sano, sin interrupciones |

### 6.4 Comparacion con el esquema anterior

| Escenario | Con `api01` unico | Con ALB + 2 nodos |
|---|---|---|
| Falla de instancia | 100% downtime hasta reemplazo manual | 0 downtime, trafico al nodo sano en ~30s |
| Deteccion de falla | Manual (monitoreo o reporte de usuario) | Automatica via health checks |
| Recuperacion | Reinicio o reemplazo manual | Manual en HA-01, automatica con ASG en HA-02 |

---

## Limpieza

> **Atencion:** El ALB, Target Group y SG del ALB son reutilizados directamente en el Lab HA-02. Si continuaras con ese lab de inmediato, **no los elimines**.

### Eliminar stack de nodos (siempre)

```bash
aws cloudformation delete-stack --stack-name cloudcuyo-ha-lab1-nodes

echo "Esperando eliminacion del stack..."
aws cloudformation wait stack-delete-complete --stack-name cloudcuyo-ha-lab1-nodes
echo "Stack eliminado."
```

### Si NO continuaras con Lab HA-02: eliminar ALB y recursos asociados

**AWS Console:**

1. **EC2 > Load Balancers** → seleccionar `cloudcuyo-api-alb` → Actions > Delete → confirmar
2. **EC2 > Target Groups** → seleccionar `cloudcuyo-api-tg` → Actions > Delete
3. **EC2 > Security Groups** → seleccionar `cloudcuyo-alb-sg` → Actions > Delete

```bash
# Obtener ARN del ALB y TG
ALB_ARN=$(aws elbv2 describe-load-balancers \
  --names cloudcuyo-api-alb \
  --query 'LoadBalancers[0].LoadBalancerArn' \
  --output text)

TG_ARN=$(aws elbv2 describe-target-groups \
  --names cloudcuyo-api-tg \
  --query 'TargetGroups[0].TargetGroupArn' \
  --output text)

# Eliminar listener, ALB y TG
aws elbv2 delete-load-balancer --load-balancer-arn $ALB_ARN
echo "Esperando eliminacion del ALB..."
aws elbv2 wait load-balancers-deleted --load-balancer-arns $ALB_ARN

aws elbv2 delete-target-group --target-group-arn $TG_ARN

# Eliminar SG del ALB
aws ec2 delete-security-group --group-id $ALB_SG_ID
```

### NO eliminar (son pre-requisitos persistentes)

- VPC, subnets, Internet Gateway, route tables
- IAM Role SSM + Instance Profile

---

## Criterios de exito

- `curl http://$ALB_DNS/health` responde con status 200 y JSON `{"node": "...", "az": "...", "status": "ok"}`
- El campo `node` alterna entre los dos Instance IDs en requests sucesivos
- El campo `az` muestra `us-east-1a` y `us-east-1b` en requests alternos
- Tras terminar un nodo, el ALB sigue respondiendo sin timeouts con el nodo sano
- El Target Group muestra el nodo terminado como `Unhealthy` y el sano como `Healthy`
- El stack `cloudcuyo-ha-lab1-nodes` se puede eliminar sin errores

---

## Proximo paso

Una vez completado este lab, la API de CloudCuyo tolera la falla de un nodo. Pero la capacidad es fija: siempre 2 instancias, sin importar la carga.

**Lab HA-02:** Reemplazar los 2 nodos fijos por un Auto Scaling Group que escala automaticamente segun la carga real → ver [`guias/guia-ha-02-asg-trafico.md`](guia-ha-02-asg-trafico.md)
