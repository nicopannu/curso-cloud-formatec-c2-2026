# Guia MS-01: Sorny — de monolito a microservicios en AWS

**Objetivo:** Partir de una aplicacion web funcional con un backend monolitico y separar sus responsabilidades en servicios independientes, cada uno en su propia EC2. El alumno observa como cambian las rutas, los contratos, las dependencias y la observabilidad cuando una aplicacion se divide en servicios con infraestructura separada.

**Duracion estimada:** 2-3 horas

**Modulo:** Modulo 2 — Clase 3: Monolito a microservicios

---

## Contexto

Sorny es una tienda de televisores. El sitio permite ver seis modelos, seleccionar uno, comprarlo y dejar datos de contacto para coordinar el envio.

Hoy, todo el backend vive en un unico proceso. Cuando un cliente compra, ese proceso:

1. recibe la solicitud;
2. genera un enlace de pago;
3. registra los datos de envio del cliente.

Eso funciona, pero tiene un problema: las responsabilidades (compras, pagos, delivery) estan mezcladas en el mismo codigo. En este laboratorio se divide ese backend en servicios independientes, **cada uno en su propia EC2**.

| Servicio | EC2 | Puerto | Que hace |
|---|---|---|---|
| `frontend` | EC2-frontend | 5000 | Muestra la tienda y gestiona el checkout |
| `monolithic-backend` | EC2-monolith | 5001 | Catalogo, compras y delivery (monolito inicial) |
| `delivery-service` | EC2-monolith | 5005 | Recibe datos de contacto para coordinar envio |
| `purchase-service` | EC2-services | 5002 | Recibe la compra y coordina el pago |
| `payment-service` | EC2-services | 5004 | Genera el enlace de pago |

Al dividir el backend aparecen preguntas nuevas:
- como decide el ALB a que servicio mandar cada request;
- como se comunican servicios que estan en distintas EC2s;
- donde miro logs cuando quiero entender que paso en el flujo completo.

---

## Arquitectura inicial (solo con reglas base)

```
Usuario
  |
  v
ALB
  |
  +-- /            -> frontend (EC2-frontend, puerto 5000)
  |
  +-- /api/*       -> backend monolitico (EC2-monolith, puerto 5001)
```

## Arquitectura final (con microservicios)

```
Usuario
  |
  v
ALB
  |
  +-- /                   -> frontend (EC2-frontend, puerto 5000)
  |
  +-- /api/purchases/*    -> purchase-service (EC2-services, puerto 5002)
  |
  +-- /api/payments/*     -> payment-service (EC2-services, puerto 5004)
  |
  +-- /api/*              -> monolith fallback (EC2-monolith, puerto 5001)
       (fallback para rutas no migradas: /api/delivery, /api/products, /api/health)
```

---

## Pre-requisitos

### Herramientas y acceso

- Acceder a [https://console.aws.amazon.com/](https://console.aws.amazon.com/)
- Region: **us-east-1 (N. Virginia)**
- Permisos para EC2, CloudFormation, CloudWatch, ELB e IAM (solo lectura)

### Recursos de red necesarios

| Recurso | Descripcion |
|---|---|
| VPC con Internet Gateway | Debe existir en la cuenta |
| Subnet publica en us-east-1a | Debe existir |
| Subnet publica en us-east-1b | Debe existir |
| IAM Role + Instance Profile con `AmazonSSMManagedInstanceCore` y `CloudWatchAgentServerPolicy` | Debe existir |

> **¿Por que necesitamos dos subnets?** El ALB necesita al menos dos subnets en distintas AZs para ser altamente disponible. La EC2 principal va en una subnet, el ALB ocupa ambas.

> **¿Por que SSM en vez de SSH?** Session Manager permite conectarse a la EC2 desde la consola de AWS sin clave SSH ni IP publica. Durante el laboratorio se usa para inspeccionar servicios y verificar configuracion.

### Anotar valores necesarios

Antes de desplegar, tener a mano desde la consola de AWS:

- **VpcId** — desde **VPC > Your VPCs**
- **SubnetAId** — ID de subnet publica en `us-east-1a`
- **SubnetBId** — ID de subnet publica en `us-east-1b`
- **SsmInstanceProfileName** — nombre del Instance Profile con SSM + CloudWatch (`cloudcuyo-ssm-role`)

---

## Fase 1: Desplegar la infraestructura Sorny

El stack `cloudformation/microservices-sorny-stack.yaml` crea todo lo necesario:

- 1 ALB publico con listener HTTP :80 (sin reglas — solo default 404)
- Security Groups para ALB y cada EC2
- 3 EC2s con Amazon Linux 2023 (frontend, monolith+delivery, servicios)
- 5 target groups (frontend, monolith, delivery, purchase, payment)
- CloudWatch Log Group
- Alarmas de status check para cada EC2

> **¿Por que el ALB arranca sin reglas?** En este laboratorio las reglas del ALB son el ejercicio principal. El stack levanta la infraestructura pero deja el ALB vacio. El alumno construye la tabla de routing completa paso a paso.

> **¿Que aplicaciones levanta cada EC2?** El template instala Python, Flask y Gunicorn. Cada servicio tiene su propio codigo y corre como proceso systemd independiente. La EC2-frontend tiene solo el frontend. La EC2-monolith tiene el monolito (5001) y el servicio de delivery (5005). La EC2-services tiene purchase (5002) y payment (5004).

### 1.1 Desplegar con CloudFormation (AWS Console)

1. Ir a **CloudFormation > Create stack > With new resources (standard)**
2. **Template source:** Upload a template file
3. Seleccionar `cloudformation/microservices-sorny-stack.yaml`
4. Click **Next**
5. **Stack name:** `sorny-microservices-stack`
6. **Parametros:**
   - **VpcId:** pegar el VpcId del lab
   - **SubnetAId:** pegar la subnet publica us-east-1a
   - **SubnetBId:** pegar la subnet publica us-east-1b
   - **InstanceType:** `t3.micro`
   - **SsmInstanceProfileName:** `cloudcuyo-ssm-role`
   - **LatestAmiId:** dejar default
   - **ProjectName:** `sorny`
   - **Environment:** `microservices-site`
   - **PurchasePaymentServiceUrl:** dejar default (`http://127.0.0.1:5004/api/payments`)
   - **CreateBaseAlbRules:** `false`
   - **CreateMicroserviceAlbRules:** `false`
7. Click **Next** dos veces
8. Click **Submit**
9. Esperar a estado **CREATE_COMPLETE** (~8-10 minutos)

### 1.2 Anotar outputs del stack

Cuando el stack llegue a **CREATE_COMPLETE**:

1. Ir a pestana **Outputs**
2. Anotar:
   - `AlbDnsName` — DNS del ALB
   - `FrontendNodeId` — ID de EC2-frontend
   - `MonolithNodeId` — ID de EC2-monolith
   - `ServicesNodeId` — ID de EC2-services
   - `FrontendTargetGroupArn` — ARN del TG frontend
   - `MonolithTargetGroupArn` — ARN del TG monolith
   - `DeliveryTargetGroupArn` — ARN del TG delivery
   - `PurchaseTargetGroupArn` — ARN del TG purchase
   - `PaymentTargetGroupArn` — ARN del TG payment

### Troubleshooting de la Fase 1

| Sintoma | Posible causa | Correccion |
|---|---|---|
| Stack queda en `CREATE_FAILED` | Parametro incorrecto (VPC, subnets) | Revisar eventos del stack en CloudFormation > Events |
| Stack timeout | Subnet sin salida a internet | Verificar ruta `0.0.0.0/0 -> IGW` en la route table |
| Error de IAM | Instance Profile no existe | Verificar el nombre del profile en IAM > Instance Profiles |

---

## Fase 2: Inspeccionar los componentes

Con el stack desplegado, antes de crear cualquier regla, inspeccionamos lo que tenemos.

### 2.1 Verificar que el ALB esta vacio

1. Abrir el navegador en `http://<AlbDnsName>/`
2. Debe aparecer: `Sorny route not configured` con HTTP 404

Esto es esperado. El ALB existe, el listener esta activo, pero no tiene ninguna regla de routing todavia. Todo request cae en la default action (fixed-response 404).

3. Ir a **EC2 > Load Balancers**
4. Seleccionar el ALB (`sorni-ms-*`)
5. Pestana **Listeners and rules** > click en **HTTP:80**
6. Debe verse solo la **Default action**: fixed-response 404

### 2.2 Verificar los target groups

1. Ir a **EC2 > Target Groups**
2. Buscar los target groups que empiezan con `sorni-`
3. Identificar los 5 TGs y sus estados:

   | Target group | EC2 | Puerto | Estado esperado |
   |---|---|---|---|
   | `sorni-Front-*` | EC2-frontend | 5000 | unused |
   | `sorni-Monol-*` | EC2-monolith | 5001 | unused |
   | `sorni-Deliv-*` | EC2-monolith | 5005 | unused |
   | `sorni-Purch-*` | EC2-services | 5002 | unused |
   | `sorni-Payme-*` | EC2-services | 5004 | unused |

   > **¿Que significa "unused"?** Un target group sin reglas del ALB que lo referencien aparece como `unused`. No es un error: los servicios estan vivos en sus EC2s, sus health checks pasan internamente, pero nadie les envia trafico desde el ALB todavia.

4. Hacer click en el TG `sorni-Front-*` > pestana **Targets**
5. La instancia debe aparecer con estado **healthy** — el servicio responde, solo falta conectar el ALB.

### 2.3 Verificar las EC2s y sus servicios

1. Ir a **EC2 > Instances**
2. Deberian verse 3 instancias: `sorny-frontend-*`, `sorny-monolith-*`, `sorny-services-*`
3. Las 3 deben estar en estado **running**

Conectarse a cada una via **Connect > Session Manager** para confirmar que los servicios estan levantados:

En la EC2-frontend:

```bash
curl -s http://127.0.0.1:5000/health
# {"service": "frontend", "status": "ok"}
```

En la EC2-monolith:

```bash
curl -s http://127.0.0.1:5001/api/health
# {"service": "monolithic-backend", "status": "ok"}

curl -s http://127.0.0.1:5005/api/delivery/health
# {"service": "delivery-service", "status": "ok"}
```

En la EC2-services:

```bash
curl -s http://127.0.0.1:5002/api/purchases/health
# {"service": "purchase-service", "status": "ok", ...}

curl -s http://127.0.0.1:5004/api/payments/health
# {"service": "payment-service", "status": "ok"}
```

> Los servicios responden localmente pero no son accesibles desde internet todavia — el ALB no les envia trafico.

---

## Fase 3: Crear las reglas base del ALB

En esta fase conectamos el ALB con el frontend y el monolito. Al terminar, el sitio debe funcionar completamente contra el backend monolitico.

### Como navegar al listener del ALB

Estos pasos son los mismos para crear cualquier regla en esta y en la siguiente fase:

1. Ir a **EC2** (menu lateral izquierdo)
2. En la seccion **Load Balancing**, click en **Load Balancers**
3. Click en el nombre del ALB (`sorni-ms-microservices-site` o similar)
4. Click en la pestana **Listeners and rules**
5. Click en el enlace **HTTP:80** — se abre la pantalla de reglas del listener

---

### 3.1 Crear regla para el frontend

Esta regla envia todo el trafico de navegacion (`/*`) al frontend en EC2-frontend.

Con el listener HTTP:80 abierto:

1. Click en **Add rule**

**Step 1 — Rule details:**
- **Name:** `frontend-rule`
- Click **Next**

**Step 2 — Add conditions:**
- Click **Add condition**
- **Condition type:** Path
- **Value:** `/*`
- Click **Confirm**
- Click **Next**

**Step 3 — Define actions:**
- **Routing action:** Forward to target groups
- **Target group:** `sorni-Front-*` (frontend, puerto 5000)
- Click **Next**

**Step 4 — Set rule priority:**
- **Priority:** `200`
- Click **Next**

Click **Create**.

---

### 3.2 Crear regla para el monolito

Esta regla envia todas las requests de API (`/api/*`) al backend monolitico en EC2-monolith.

1. Click en **Add rule**

**Step 1 — Rule details:**
- **Name:** `monolith-api-rule`
- Click **Next**

**Step 2 — Add conditions:**
- Click **Add condition**
- **Condition type:** Path
- **Value:** `/api/*`
- Click **Confirm**
- Click **Next**

**Step 3 — Define actions:**
- **Routing action:** Forward to target groups
- **Target group:** `sorni-Monol-*` (monolith, puerto 5001)
- Click **Next**

**Step 4 — Set rule priority:**
- **Priority:** `100`
- Click **Next**

Click **Create**.

---

### 3.3 Verificar el orden de las reglas base

La lista de reglas debe quedar:

| Prioridad | Condicion de path | Target group | EC2 |
|---|---|---|---|
| 100 | `/api/*` | sorni-Monol-* | EC2-monolith (5001) |
| 200 | `/*` | sorni-Front-* | EC2-frontend (5000) |
| default | — | fixed-response 404 | — |

> **¿Por que /api/* tiene prioridad 100 y /* tiene 200?** El ALB evalua las reglas de menor a mayor numero. Si /* tuviera prioridad mas alta (menor numero), captaria todos los requests incluyendo los de `/api/`. Con el orden correcto: primero se evalua `/api/*` y captura las APIs; si no coincide, cae en `/*` que captura el resto.

### 3.4 Verificar el sitio con el monolito

1. Ir a **EC2 > Target Groups**
2. `sorni-Front-*` y `sorni-Monol-*` deben pasar de `unused` a **healthy** en 1-2 minutos

3. Abrir el navegador en `http://<AlbDnsName>/`
4. Deben verse los seis televisores Sorny

5. Probar la compra completa:
   - Click en **Comprar ahora** en cualquier televisor
   - Completar el formulario de pago
   - Debe verse: "¡Pago aprobado! Te vamos a contactar para coordinar el envio"

6. Confirmar que el monolito procesa la compra:
   - `http://<AlbDnsName>/api/products` → devuelve `"backend": "monolithic-backend"`
   - `http://<AlbDnsName>/api/health` → devuelve `{"service": "monolithic-backend", "status": "ok"}`

> **¿Que paso atras?** El ALB recibio el POST `/api/purchases`, evaluo las reglas en orden: la prioridad 100 (`/api/*`) coincidio y desvio el request al monolito. Todo el flujo de compra paso por EC2-monolith.

---

## Fase 4: Crear las reglas de microservicios

Ahora agregamos reglas mas especificas que desvian compras y pagos a los servicios en EC2-services. Al ser mas especificas y tener menor numero de prioridad, van a "ganarle" a la regla `/api/*` del monolito.

### 4.1 Crear regla para purchase-service

1. Click en **Add rule**

**Step 1 — Rule details:**
- **Name:** `purchase-service-rule`
- Click **Next**

**Step 2 — Add conditions:**
- Click **Add condition**
- **Condition type:** Path
- **Value:** `/api/purchases`
- Click **Add new value** (el `+` o "Add another value")
- **Value:** `/api/purchases/*`
- Click **Confirm**
- Click **Next**

**Step 3 — Define actions:**
- **Routing action:** Forward to target groups
- **Target group:** `sorni-Purch-*` (purchase-service, puerto 5002)
- Click **Next**

**Step 4 — Set rule priority:**
- **Priority:** `10`
- Click **Next**

Click **Create**.

---

### 4.2 Crear regla para payment-service

1. Click en **Add rule**

**Step 1 — Rule details:**
- **Name:** `payment-service-rule`
- Click **Next**

**Step 2 — Add conditions:**
- Click **Add condition**
- **Condition type:** Path
- **Value:** `/api/payments`
- Click **Add new value**
- **Value:** `/api/payments/*`
- Click **Confirm**
- Click **Next**

**Step 3 — Define actions:**
- **Routing action:** Forward to target groups
- **Target group:** `sorni-Payme-*` (payment-service, puerto 5004)
- Click **Next**

**Step 4 — Set rule priority:**
- **Priority:** `30`
- Click **Next**

Click **Create**.

---

### 4.3 Verificar el orden final de todas las reglas

La tabla completa debe quedar:

| Prioridad | Condicion de path | Target group | EC2 |
|---|---|---|---|
| 10 | `/api/purchases` o `/api/purchases/*` | sorni-Purch-* | EC2-services (5002) |
| 30 | `/api/payments` o `/api/payments/*` | sorni-Payme-* | EC2-services (5004) |
| 100 | `/api/*` | sorni-Monol-* | EC2-monolith (5001) |
| 200 | `/*` | sorni-Front-* | EC2-frontend (5000) |
| default | — | fixed-response 404 | — |

> **¿Por que las reglas de microservicios tienen prioridad 10 y 30?** Al tener numeros mas bajos, se evaluan antes que la regla 100 (`/api/*`). Cuando llega un request a `/api/purchases/nueva`, la regla 10 la captura y la manda a purchase-service. Sin esta prioridad, la regla 100 la interceptaria primero y la mandaria al monolito.

### 4.4 Verificar health de los nuevos target groups

1. Ir a **EC2 > Target Groups**
2. `sorni-Purch-*` y `sorni-Payme-*` deben pasar a **healthy** en 1-2 minutos

---

## Fase 5: Probar el flujo con microservicios

### 5.1 Probar la compra

1. Ir al sitio `http://<AlbDnsName>/`
2. Click en **Comprar ahora** en cualquier televisor
3. Completar el formulario y confirmar

La compra debe completarse exitosamente, igual que antes.

### 5.2 Confirmar que paso por purchase-service

La diferencia ahora esta en quien proceso la compra. Probar el endpoint directamente:

```
POST http://<AlbDnsName>/api/purchases
Content-Type: application/json

{"sku": "sorni-luma-32", "customer": "test@sorny.local"}
```

La respuesta debe incluir `"backend": "purchase-service"` — confirma que el request fue procesado por el servicio separado en EC2-services, no por el monolito.

Antes de crear la regla de prioridad 10, esa misma request devolveria `"backend": "monolithic-backend"`.

### 5.3 Verificar que el monolito sigue activo como fallback

- `http://<AlbDnsName>/api/products` — devuelve `"backend": "monolithic-backend"` (sin regla propia, cae en prioridad 100)
- `http://<AlbDnsName>/api/health` — devuelve el health del monolito

> **¿Por que /api/products sigue en el monolito?** La migracion es parcial e intencional. Solo `/api/purchases/*` y `/api/payments/*` fueron migrados. El resto de `/api/*` sigue yendo al monolito como fallback. Esto permite migrar servicio por servicio sin cambiar todo al mismo tiempo.

---

## Fase 6: Observar con CloudWatch

Con todos los microservicios activos, cada servicio escribe sus propios logs en streams separados dentro del mismo log group.

### 6.1 Ubicar el log group

1. Ir a **CloudWatch > Log groups**
2. Buscar `/sorny/microservices-site/site`
3. Abrir el log group — se ven los streams por servicio:
   - `frontend`
   - `monolithic-backend`
   - `delivery-service`
   - `purchase-service`
   - `payment-service`

### 6.2 Ver los logs de una compra

1. Abrir el stream `purchase-service`
2. Buscar una entrada reciente:
   ```
   purchase sku=sorni-luma-32 customer=test@sorny.local
   purchase created pid=pur-abc12345 sku=sorni-luma-32
   ```

3. Abrir el stream `monolithic-backend`
4. Notar que NO hay registro de esa compra — fue a purchase-service, no al monolito

### 6.3 Comparar request counts por target group

1. Ir a **EC2 > Target Groups** > `sorni-Purch-*` > pestana **Monitoring**
2. Revisar `RequestCount` — debe mostrar picos correspondientes a las compras realizadas
3. Comparar con `sorni-Monol-*` > **Monitoring**
4. `RequestCount` del monolith debe reflejar solo requests a `/api/products`, `/api/health`, `/api/delivery`

> **¿Por que es importante tener logs separados por servicio?** En un monolito, todos los logs van a un solo lugar. En microservicios, cada servicio tiene su propio stream. Esto permite filtrar rapidamente: si una compra falla, se abre `purchase-service`. Si el catalogo no carga, se abre `monolithic-backend`. No hay que buscar en un log gigante mezclado.

---

## Limpieza

1. Ir a **CloudFormation > Stacks**
2. Seleccionar `sorny-microservices-stack`
3. Click **Delete** > confirmar
4. Esperar a que desaparezca (~5 minutos)

**NO eliminar** recursos persistentes del curso: VPC, subnets, Internet Gateway, route tables, IAM roles.

---

## Criterios de exito

- El sitio devuelve 404 al abrir por primera vez (ALB sin reglas)
- Despues de crear las reglas base, el sitio Sorny muestra los 6 televisores
- La compra funciona completamente contra el monolito (`"backend": "monolithic-backend"`)
- Los target groups de frontend y monolith pasan a healthy al crear sus reglas
- Los target groups de purchase y payment pasan a healthy al crear las reglas de microservicios
- Despues de crear las reglas de microservicios, `POST /api/purchases` devuelve `"backend": "purchase-service"`
- `GET /api/products` sigue devolviendo `"backend": "monolithic-backend"` (no fue migrado)
- Los logs de CloudWatch muestran streams separados por servicio
- Las compras aparecen en el stream `purchase-service`, no en `monolithic-backend`
- Se puede explicar por que el orden de prioridad de las reglas del ALB importa
- Se puede explicar que es una migracion parcial y por que tiene sentido hacerlo por etapas
