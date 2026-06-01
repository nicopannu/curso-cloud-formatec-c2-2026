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

### Recursos de red necesarios

Este lab requiere dos Availability Zones completas (public + private cada una). La VPC del lab ya tiene subnets en AZ-A. La AZ-B se crea como parte de los pre-requisitos de este lab.

> **Antes de comenzar:** Tener a mano los IDs de la VPC y las subnets. Se pueden consultar en **VPC > Your VPCs** y **VPC > Subnets**.

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

### Pre-req A: Crear Public Subnet AZ-B y asociarla a la route table publica (`10.0.2.0/24`)

> **¿Por que necesitamos una segunda AZ?** Un ALB necesita estar en al menos dos Availability Zones para ser altamente disponible. Una AZ es un datacenter fisicamente separado dentro de la region. Si todo esta en una sola AZ y esa falla, el ALB tambien cae. Distribuir en dos AZs significa que una puede fallar sin afectar el servicio.

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
9. Identificar y seleccionar la **route table publica**:
   - Debe tener una ruta `0.0.0.0/0 → igw-xxxxx`
   - Normalmente ya esta asociada a la subnet publica AZ-A (`10.0.0.0/24`)
10. Ir a pestana **Subnet associations**
11. Click **Edit subnet associations**
12. Marcar la nueva subnet `cloudcuyo-public-us-east-1b`
13. Click **Save associations**
14. Volver a la pestana **Subnet associations** y confirmar que la subnet AZ-B aparece asociada a la route table publica

> **¿Por que asociar la subnet a la route table publica?** Una subnet "publica" es simplemente una subnet cuya route table tiene una ruta `0.0.0.0/0 → IGW`. Sin esa ruta, el trafico de internet no llega. Asociar la nueva subnet a la misma route table publica garantiza que el ALB pueda recibir trafico externo desde ambas AZs.

---

### Pre-req B: Crear Private Subnet AZ-B y asociarla a la route table privada (`10.0.3.0/24`)

> **¿Por que creamos la subnet privada si los nodos van en publicas?** La subnet privada AZ-B es un pre-requisito para labs futuros (HA-02 y HA-03) y para contar con la estructura de red correcta (cada AZ deberia tener una subnet publica y una privada). No la usamos en este lab pero la creamos ahora para no tener que interrumpir el flujo despues.

1. Ir a **VPC > Subnets > Create subnet**
2. Seleccionar la misma VPC
3. Configurar:
   - **Subnet name:** `cloudcuyo-private-us-east-1b`
   - **Availability Zone:** `us-east-1b`
   - **IPv4 CIDR block:** `10.0.3.0/24`
4. Click en **Create subnet**
5. Ir a **VPC > Route tables**
6. Identificar y seleccionar la **route table privada** del lab:
   - No debe tener ruta publica `0.0.0.0/0 → igw-xxxxx`
   - Normalmente ya esta asociada a la subnet privada AZ-A (`10.0.1.0/24`)
   - Si el entorno tuviera NAT o VPC endpoints, podria tener rutas privadas adicionales; lo importante es que no apunte directo al Internet Gateway
7. Ir a pestana **Subnet associations**
8. Click **Edit subnet associations**
9. Marcar la nueva subnet `cloudcuyo-private-us-east-1b`
10. Click **Save associations**
11. Volver a la pestana **Subnet associations** y confirmar que la subnet AZ-B aparece asociada a la route table privada

> **Validacion antes de seguir:** En **VPC > Route tables**, la subnet publica AZ-B debe estar asociada a la route table publica y la subnet privada AZ-B debe estar asociada a la route table privada. Si alguna queda sin asociacion explicita, AWS usara la route table principal de la VPC, que puede no ser la correcta para el lab.

---

### Pre-req C: Verificar o crear IAM Role SSM

> **¿Por que necesitan las EC2 un IAM Role?** Por defecto, una instancia EC2 no tiene permisos para interactuar con otros servicios de AWS. El IAM Role actua como una "identidad" que se asigna a la instancia y le otorga permisos especificos. En este caso, `AmazonSSMManagedInstanceCore` permite al SSM Agent de la instancia comunicarse con el servicio Systems Manager sin necesidad de una clave SSH ni una IP publica accesible. Esto es mas seguro y operativamente mas simple que gestionar claves SSH.

**Verificar si ya existe:**

1. Ir a **IAM > Roles**
2. Buscar un rol con permisos `AmazonSSMManagedInstanceCore`
3. Si existe, anotar su nombre. Si no existe, crearlo:

**Si no existe, crearlo:**

1. Ir a **IAM > Roles > Create role**
2. **Trusted entity type:** AWS service
3. **Use case:** EC2
4. **Permissions:** agregar `AmazonSSMManagedInstanceCore`
5. **Role name:** `cloudcuyo-ssm-role`
6. Click **Create role**

**Verificar el Instance Profile:**

Al crear un rol con "Use case: EC2" en la consola, AWS crea automaticamente un Instance Profile con el mismo nombre. Para verificarlo:

1. Ir a **IAM > Roles > cloudcuyo-ssm-role**
2. En la seccion **Instance profiles**, confirmar que aparece `cloudcuyo-ssm-role`
3. Si el Instance Profile no aparece automaticamente al crear el rol, ir a **IAM > Roles > cloudcuyo-ssm-role > Instance profiles** y verificar que este asociado. En ese caso excepcional, contactar al instructor.

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
4. En **Outbound rules:** verificar que exista una regla de salida:
   - **Type:** All traffic
   - **Destination:** `0.0.0.0/0`
5. Si la regla outbound no aparece, agregarla manualmente con **Add rule**
6. Click **Create security group**
7. Anotar el **Security Group ID** (formato `sg-xxxxxxxxx`)

> **¿Por que el SG del ALB necesita outbound?** El ALB recibe trafico en puerto 80 desde Internet, pero despues debe abrir conexiones salientes hacia los nodos API en puerto 5000. Security Groups son stateful, pero igual necesitan una regla outbound que permita iniciar esa conexion hacia los targets. En este lab se deja la regla outbound default `All traffic → 0.0.0.0/0` para simplificar. En produccion se podria restringir a `TCP 5000` hacia el SG de los nodos.

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
   - **VpcId:** pegar el ID de la VPC (desde VPC > Your VPCs)
   - **SubnetAId:** pegar el ID de la subnet publica AZ-A
   - **SubnetBId:** pegar el ID de la subnet publica AZ-B (recien creada)
   - **AlbSgId:** pegar el Security Group ID del ALB (del paso 1.1)
   - **SsmInstanceProfile:** pegar `cloudcuyo-ssm-role` (o el nombre del Instance Profile SSM)
7. Click **Next** dos veces
8. Si la consola muestra algun checkbox de **Capabilities / IAM acknowledgment**, marcarlo. Si no aparece, es normal: este template usa un Instance Profile existente pero no crea recursos IAM.
9. Click **Submit**
10. Esperar a estado **CREATE_COMPLETE** (~3-5 minutos)
11. Ir a pestana **Outputs** y anotar:
    - **ApiNode1Ip:** IP privada del nodo 1 (AZ-A)
    - **ApiNode2Ip:** IP privada del nodo 2 (AZ-B)
    - **ApiNode1Id:** Instance ID del nodo 1
    - **ApiNode2Id:** Instance ID del nodo 2
    - **ApiNodeSgId:** Security Group ID de los nodos creados por este stack

> **Importante para HA-02:** El `ApiNodeSgId` pertenece al stack `cloudcuyo-ha-lab1-nodes`. Cuando se elimina el stack al comenzar HA-02, ese Security Group tambien se elimina. En HA-02 se crea un nuevo SG manual para los nodos del ASG.

> **Nota:** Las instancias recien lanzadas pueden tardar 1-2 minutos en inicializar la API via user-data. Si se intenta registrarlas en el Target Group de inmediato, pueden aparecer en estado `Initial`. Eso es normal.

### Troubleshooting de la Fase 2

| Sintoma | Posible causa | Correccion |
|---|---|---|
| Stack queda en `CREATE_FAILED` | Parametro incorrecto (subnet ID, SG ID) | Revisar eventos del stack en CloudFormation > Events |
| No aparece checkbox de capacidades IAM | El template no crea recursos IAM | Es normal; continuar con **Submit** |
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
8. Anotar el **ARN del Target Group** (visible en la pagina de detalle del TG — se reutiliza en Lab HA-02)

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

### Troubleshooting de la Fase 4

| Sintoma | Posible causa | Correccion |
|---|---|---|
| Error "Subnet must be in two different AZs" | Se selecciono la misma AZ dos veces o una sola subnet | Asegurarse de marcar `us-east-1a` y `us-east-1b` con subnets distintas |
| ALB queda en estado `Provisioning` por mas de 10 min | Problema de red o cuota | Revisar eventos del ALB en CloudWatch o contactar al instructor |
| DNS del ALB no resuelve aun | DNS propagation | Esperar 1-2 minutos antes de intentar acceder |

---

## Fase 5: Validar distribucion de trafico

Una vez que el ALB esta Active y los dos targets estan Healthy, comprobar que el trafico se distribuye entre ambos nodos.

### 5.1 Verificar estado de los targets

1. Ir a **EC2 > Target Groups > cloudcuyo-api-tg**
2. Pestana **Targets**
3. Ambas instancias deben estar en estado **Healthy**

### 5.2 Probar distribucion round-robin

1. Abrir el navegador en `http://<DNS-del-ALB>/health` (reemplazar `<DNS-del-ALB>` por el DNS name copiado en el paso 4.1.9)
2. Refrescar la pagina varias veces (F5 o Ctrl+R)
3. Observar la respuesta JSON en el navegador:

```json
{
    "node": "i-0a1b2c3d4e5f67890",
    "az": "us-east-1a",
    "status": "ok"
}
```

4. Si el campo `node` cambia entre refreshes (alterna entre dos Instance IDs distintos), el ALB esta distribuyendo el trafico correctamente.
5. El campo `az` debe mostrar `us-east-1a` y `us-east-1b` en requests alternos.

> **¿Por que el campo `node` alterna?** El ALB usa round-robin por defecto: cada request va a una instancia diferente en orden rotatorio. El campo `node` contiene el Instance ID de la EC2 que respondio (obtenido del IMDS al arrancar). Ver que alterna entre dos Instance IDs distintos confirma que el ALB esta distribuyendo el trafico y que ambos nodos estan procesando requests.

---

## Fase 6: Simular falla de un nodo y observar failover

Este experimento ilustra la ventaja clave del ALB sobre un servidor unico: cuando un nodo falla, el ALB detecta la falla via health checks y deja de enviarle trafico automaticamente.

### 6.1 Terminar uno de los nodos

1. Ir a **EC2 > Instances**
2. Seleccionar `cloudcuyo-api-node-1` (o el nodo en AZ-A)
3. **Instance state > Terminate instance > Terminate**

> **¿Que diferencia hay entre Stop y Terminate?** Stop apaga la VM pero la conserva (como "hibernar"). Terminate la destruye permanentemente. Para simular una falla real (crash de hardware, falla de zona), usamos Terminate. El ALB detecta la falla cuando los health checks fallan —no cuando la instancia se termina— asi que el comportamiento es el mismo en ambos casos.

### 6.2 Observar el comportamiento del ALB

**Monitorear el trafico desde el navegador:**

1. Abrir `http://<DNS-del-ALB>/health` en el navegador
2. Refrescar cada 5-10 segundos
3. Durante los primeros ~30 segundos puede haber algun timeout o error de conexion (normal — el ALB aun no detecto la falla)
4. Pasados ~30s, todas las respuestas deben venir del nodo sano (campo `node` siempre el mismo Instance ID)
5. No debe haber interrupciones prolongadas — solo el nodo sano sigue respondiendo

**Monitorear el estado del Target Group:**

1. Abrir **EC2 > Target Groups > cloudcuyo-api-tg > Targets** en otra pestana del navegador
2. Refrescar la pagina cada 15 segundos para observar el cambio de estado
3. La instancia terminada puede pasar por `draining`, `Unhealthy`, `unused` o desaparecer de la lista de targets. Lo importante es que el Target Group quede con un solo target `Healthy` y el ALB deje de enviar trafico al nodo terminado.

### 6.3 Secuencia esperada de eventos

| Tiempo | Que sucede |
|---|---|
| T+0s | Instancia termina |
| T+15-30s | ALB health check falla (primer check) |
| T+30-45s | ALB marca el target como `Unhealthy` (umbral=2 checks fallidos) |
| T+45s+ | ALB solo envia trafico al nodo sano |
| Browser refresh | `node` muestra solo el ID del nodo sano, sin interrupciones |

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

1. Ir a **CloudFormation > Stacks**
2. Seleccionar `cloudcuyo-ha-lab1-nodes`
3. Click **Delete** > confirmar
4. Esperar a que el stack desaparezca de la lista (~2-3 minutos)

### Conservar ALB, Target Group y SG del ALB

No eliminar en este punto:

- ALB `cloudcuyo-api-alb`
- Target Group `cloudcuyo-api-tg`
- Security Group `cloudcuyo-alb-sg`

Estos recursos se reutilizan directamente en HA-02. La limpieza completa queda documentada al final de HA-03, cuando ya no se necesitan para los labs siguientes.

### NO eliminar (son pre-requisitos persistentes)

- VPC, subnets, Internet Gateway, route tables
- IAM Role SSM + Instance Profile

---

## Criterios de exito

- Abriendo `http://<DNS-del-ALB>/health` en el navegador, responde con status 200 y JSON `{"node": "...", "az": "...", "status": "ok"}`
- El campo `node` alterna entre los dos Instance IDs en refreshes sucesivos
- El campo `az` muestra `us-east-1a` y `us-east-1b` en requests alternos
- Tras terminar un nodo, el ALB sigue respondiendo sin timeouts con el nodo sano
- El Target Group queda con el nodo sano como `Healthy`; el nodo terminado puede aparecer como `draining`/`Unhealthy`/`unused` durante unos minutos o desaparecer de la lista
- El stack `cloudcuyo-ha-lab1-nodes` se puede eliminar sin errores

---

## Proximo paso

Una vez completado este lab, la API de CloudCuyo tolera la falla de un nodo. Pero la capacidad es fija: siempre 2 instancias, sin importar la carga.

**Lab HA-02:** Reemplazar los 2 nodos fijos por un Auto Scaling Group que escala automaticamente segun la carga real → ver [`guias/guia-ha-02-asg-trafico.md`](guia-ha-02-asg-trafico.md)
