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

## Arquitectura inicial

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

## Arquitectura final esperada

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
- **SsmInstanceProfileName** — nombre del Instance Profile con SSM + CloudWatch (ej: `sorni-microservices-ec2-profile` o el que exista en la cuenta)

---

## Fase 1: Desplegar la infraestructura Sorny

El stack `cloudformation/microservices-sorny-stack.yaml` crea todo lo necesario:

- 1 ALB publico con listener HTTP :80
- Security Groups para ALB y cada EC2
- 3 EC2s con Amazon Linux 2023 (frontend, monolith+delivery, servicios)
- 5 target groups (frontend, monolith, delivery, purchase, payment)
- Reglas base del ALB (`/api/*` -> monolith, `/*` -> frontend)
- CloudWatch Log Group
- Alarmas de status check para cada EC2

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
   - **SsmInstanceProfileName:** pegar el nombre del Instance Profile
   - **LatestAmiId:** dejar default
   - **ProjectName:** `sorny`
   - **Environment:** `microservices-site`
   - **PurchasePaymentServiceUrl:** dejar default (`http://127.0.0.1:5004/api/payments`)
   - **CreateBaseAlbRules:** `true`
   - **CreateMicroserviceAlbRules:** `false`
7. Click **Next** dos veces
8. Click **Submit**
9. Esperar a estado **CREATE_COMPLETE** (~8-10 minutos)

> **¿Por que CreateBaseAlbRules=true y CreateMicroserviceAlbRules=false?** Con `CreateBaseAlbRules=true`, el sitio arranca funcionando contra el monolito. Con `CreateMicroserviceAlbRules=false`, los alumnos crean las reglas de microservicios manualmente como parte del ejercicio.

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

## Fase 2: Verificar el sitio y el flujo completo

### 2.1 Abrir el sitio

1. Abrir el navegador en `http://<AlbDnsName>/`
2. Deberian verse los seis televisores Sorny con diseño moderno

### 2.2 Probar la compra completa

1. Click en **Comprar ahora** en cualquier televisor
2. Deberia aparecer un modal con "Preparando pago..."
3. Luego el modal muestra el formulario de pago con campos de tarjeta, nombre, email, telefono y direccion de envio
4. Completar los datos y click en **Pagar y coordinar envio**
5. Deberia verse una pantalla de exito: "¡Pago aprobado! Te vamos a contactar para coordinar el envio"

> **¿Que paso atras?** El frontend envio un POST a `/api/purchases`. El monolito (EC2-monolith, puerto 5001) recibio la solicitud, genero un ID de compra y un enlace de pago. Luego el frontend mostro el formulario de checkout. Al confirmar, envio un POST a `/api/delivery` que el monolito tambien proceso. Todo paso por el mismo backend monolitico en una sola EC2.

### 2.3 Ver los endpoints del monolito

Probar directamente:

- `http://<AlbDnsName>/api/products` — lista de 6 modelos con `"backend": "monolithic-backend"`
- `http://<AlbDnsName>/api/health` — `{"service": "monolithic-backend", "status": "ok"}`

> **¿Por que aparece "monolithic-backend"?** Cada servicio responde con un campo `backend` que indica quien proceso la request. Cuando se separen las rutas, ese campo mostrara `purchase-service` o `payment-service` en vez de `monolithic-backend`.

---

## Fase 3: Inspeccionar los componentes en AWS

### 3.1 Ubicar los target groups

1. Ir a **EC2 > Target Groups**
2. Buscar los target groups que empiezan con `sorni-`
3. Identificar los 5 TGs:
   - `sorni-Front-*` (frontend, EC2-frontend, puerto 5000)
   - `sorni-Monol-*` (monolith, EC2-monolith, puerto 5001)
   - `sorni-Deliv-*` (delivery, EC2-monolith, puerto 5005)
   - `sorni-Purch-*` (purchase, EC2-services, puerto 5002)
   - `sorni-Payme-*` (payment, EC2-services, puerto 5004)
4. Verificar estado:
   - `frontend` y `monolith` deben estar **healthy**
   - `delivery`, `purchase`, `payment` pueden estar **unused** (sin reglas del ALB)

> **¿Que significa "unused"?** Un target group sin reglas del ALB que lo referencien aparece como `unused`. No es un error: los servicios estan vivos en sus EC2s, sus health checks pasan, pero nadie les envia trafico desde el ALB todavia.

### 3.2 Ver las EC2s y sus servicios

1. Ir a **EC2 > Instances**
2. Deberian verse 3 instancias: `sorny-frontend-*`, `sorny-monolith-*`, `sorny-services-*`
3. Entrar a cada una via **Connect > Session Manager**

En la EC2-frontend:

```bash
curl -s http://127.0.0.1:5000/health
```

En la EC2-monolith:

```bash
curl -s http://127.0.0.1:5001/api/health
curl -s http://127.0.0.1:5005/api/delivery/health
```

En la EC2-services:

```bash
curl -s http://127.0.0.1:5002/api/purchases/health
curl -s http://127.0.0.1:5004/api/payments/health
```

> **¿Por que entrar por Session Manager?** No requiere puertos abiertos ni claves SSH. La EC2 solo necesita el IAM Role con `AmazonSSMManagedInstanceCore`.

### 3.3 Revisar las reglas actuales del ALB

1. Ir a **EC2 > Load Balancers**
2. Seleccionar el ALB (`sorni-ms-*`)
3. Pestana **Listeners and rules** > click en el enlace `HTTP:80`
4. Deberian verse:
   - **Priority 100:** `/api/*` -> monolith TG
   - **Priority 200:** `/*` -> frontend TG
   - **Default:** fixed-response 404

> **¿Por que el default es 404?** Es una buena practica: el ALB no envia trafico a ningun lugar que no este explicitamente configurado. Si llega una ruta desconocida, responde 404 en vez de redirigir a algun servicio por error.

---

## Fase 4: Crear las reglas path-based del ALB

El ALB decide a que target group enviar cada request segun la ruta. En esta fase se crean las reglas que desvian el trafico de compras y pagos hacia los servicios en EC2-services.

> **¿Por que crear las reglas manualmente si ya existen target groups?** Un target group solo define un destino posible. Las reglas del listener son las que conectan las rutas con los destinos. Sin reglas, el TG existe pero nadie le envia trafico.

### 4.0 Navegar al listener del ALB

1. Ir a **EC2** (menu lateral izquierdo)
2. En la seccion **Load Balancing**, click en **Load Balancers**
3. Click en el nombre del ALB (`sorni-ms-microservices-site` o similar)
4. Click en la pestana **Listeners and rules**
5. Click en el enlace **HTTP:80** — se abre la pantalla de reglas del listener

Queda abierta la lista de reglas. Se ven las dos reglas base (priority 100 y 200) y la default action.

---

### 4.1 Crear regla para purchase-service

Esta regla envia las solicitudes de compra a `purchase-service` en EC2-services.

1. Click en el boton **Add rule** (arriba a la derecha)

**Step 1 — Rule details:**
- **Name:** `purchase-service-rule`
- Tags: opcional
- Click **Next**

**Step 2 — Add conditions:**
- Click **Add condition**
- **Condition type:** Path
- En el campo de valores ingresar: `/api/purchases`
- Click **Add new value** (el `+` o "Add another value")
- Ingresar: `/api/purchases/*`
- Click **Confirm**
- Click **Next**

**Step 3 — Define actions:**
- **Routing action:** Forward to target groups
- En **Target group**, seleccionar `sorni-Purch-*` (purchase-service, puerto 5002)
- Dejar weight en 1
- Click **Next**

**Step 4 — Set rule priority:**
- **Priority:** `10`
- Click **Next**

**Review:** verificar que aparece:
- Name: `purchase-service-rule`
- Condition: Path is `/api/purchases` OR `/api/purchases/*`
- Action: Forward to `sorni-Purch-*`
- Priority: 10

Click **Create**.

---

### 4.2 Crear regla para payment-service

Esta regla envia las solicitudes de pago a `payment-service` en EC2-services.

1. Click en **Add rule** nuevamente

**Step 1 — Rule details:**
- **Name:** `payment-service-rule`
- Click **Next**

**Step 2 — Add conditions:**
- Click **Add condition**
- **Condition type:** Path
- Ingresar: `/api/payments`
- Click **Add new value**
- Ingresar: `/api/payments/*`
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

### 4.3 Verificar el orden final de reglas

Despues de crear ambas reglas, la lista debe quedar asi:

| Prioridad | Condicion de path | Target group | EC2 |
|---|---|---|---|
| 10 | `/api/purchases` o `/api/purchases/*` | sorni-Purch-* | EC2-services (5002) |
| 30 | `/api/payments` o `/api/payments/*` | sorni-Payme-* | EC2-services (5004) |
| 100 | `/api/*` | sorni-Monol-* | EC2-monolith (5001) |
| 200 | `/*` | sorni-Front-* | EC2-frontend (5000) |
| default | — | fixed-response 404 | — |

> **¿Por que importa el orden de prioridad?** El ALB evalua las reglas de menor a mayor numero. La regla de prioridad 10 se evalua primero. Si una request llega a `/api/purchases/nueva`, la regla 10 la captura antes de que llegue a la regla 100 (`/api/*`). Sin la prioridad correcta, el monolito seguiria recibiendo todo el trafico de `/api/*` incluyendo compras.

### 4.4 Verificar health de los nuevos target groups

1. Ir a **EC2 > Target Groups**
2. `purchase` y `payment` deben pasar de `unused` a **healthy** en los proximos 1-2 minutos

> **¿Por que tarda en pasar a healthy?** El ALB hace health checks periodicos (cada 30 segundos por default). Cuando agrega una regla que apunta a un TG, el ALB comienza a verificar el health del target. Hasta que no pase el primer check, el estado es `initial`.

---

## Fase 5: Probar el flujo con microservicios

Ahora que las reglas estan en lugar, las compras deben ser procesadas por `purchase-service` en EC2-services en vez del monolito.

### 5.1 Probar la compra

1. Ir al sitio `http://<AlbDnsName>/`
2. Click en **Comprar ahora** en cualquier televisor
3. Completar el formulario de pago y confirmar

**Resultado esperado:** La compra se completa exitosamente, igual que antes.

### 5.2 Confirmar que paso por purchase-service

Probar el endpoint directamente:

```
POST http://<AlbDnsName>/api/purchases
Content-Type: application/json

{"sku": "sorni-luma-32", "customer": "test@sorny.local"}
```

La respuesta debe incluir `"backend": "purchase-service"` — confirma que el request fue procesado por el servicio separado en EC2-services, no por el monolito.

Antes de crear las reglas, esa misma request devolveria `"backend": "monolithic-backend"`.

### 5.3 Verificar que el monolito sigue activo como fallback

- `http://<AlbDnsName>/api/products` — sigue devolviendo `"backend": "monolithic-backend"` (la ruta `/api/products` no tiene regla propia, cae en priority 100 `/api/*` → monolith)
- `http://<AlbDnsName>/api/health` — sigue devolviendo el health del monolito

> **¿Por que /api/products sigue en el monolito?** La migracion es parcial e intencional. Solo `/api/purchases/*` y `/api/payments/*` fueron migrados. El resto de `/api/*` sigue yendo al monolito como fallback. Asi se puede migrar servicio por servicio sin necesidad de cambiar todo al mismo tiempo.

---

## Fase 6: Observar con CloudWatch

Con los microservicios activos, cada servicio escribe sus propios logs en streams separados dentro del mismo log group.

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
2. Buscar una entrada reciente — debe mostrar algo como:
   ```
   purchase sku=sorni-luma-32 customer=test@sorny.local
   purchase created pid=pur-abc12345 sku=sorni-luma-32
   payment link pid=pur-abc12345 amt=189999
   ```

3. Abrir el stream `monolithic-backend`
4. Notar que NO hay registro de la compra que hiciste via microservicio — esa request fue a purchase-service, no al monolito

### 6.3 Comparar con logs del monolito

1. Realizar una compra nueva directamente al monolito (necesita eliminar temporalmente la regla de purchase del ALB o hacerlo via curl):
   ```bash
   curl -s -X POST http://<AlbDnsName>/api/health
   ```
2. Los logs de health checks y requests a `/api/products` siguen apareciendo en `monolithic-backend`

> **¿Por que es importante tener logs separados por servicio?** En un monolito, todos los logs van a un solo lugar. En microservicios, cada servicio tiene su propio stream. Esto permite filtrar rapidamente: si una compra falla, se abre `purchase-service`. Si el catalogo no carga, se abre `monolithic-backend`. No hay que buscar en un log gigante mezclado.

### 6.4 Revisar metricas del ALB por target group

1. Ir a **EC2 > Target Groups** > `sorni-Purch-*` > pestana **Monitoring**
2. Revisar `RequestCount` — debe mostrar picos correspondientes a las compras realizadas
3. Comparar con `sorni-Monol-*` > **Monitoring**
4. Notar que `RequestCount` del monolith disminuyo para las rutas migradas

---

## Limpieza

1. Ir a **CloudFormation > Stacks**
2. Seleccionar `sorny-microservices-stack`
3. Click **Delete** > confirmar
4. Esperar a que desaparezca (~5 minutos)

**NO eliminar** recursos persistentes del curso: VPC, subnets, Internet Gateway, route tables, IAM roles.

---

## Criterios de exito

- El sitio Sorny responde con los 6 televisores en `http://<AlbDnsName>/`
- La compra funciona con el monolito antes de crear las reglas de microservicios
- Los target groups de frontend y monolith estan healthy desde el inicio
- Los target groups de purchase y payment pasan a healthy al crear las reglas del ALB
- Despues de crear las reglas, `POST /api/purchases` devuelve `"backend": "purchase-service"`
- `GET /api/products` sigue devolviendo `"backend": "monolithic-backend"` (no fue migrado)
- Los logs de CloudWatch muestran streams separados por servicio
- Las compras aparecen en el stream `purchase-service`, no en `monolithic-backend`
- Se puede explicar por que el orden de prioridad de las reglas del ALB importa
- Se puede explicar que es una migracion parcial y por que tiene sentido hacerlo por etapas
