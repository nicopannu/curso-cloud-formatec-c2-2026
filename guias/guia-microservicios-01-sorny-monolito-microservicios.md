# Guia MS-01: Sorny — de monolito a microservicios en AWS

**Objetivo:** Partir de una aplicacion web funcional con un backend monolitico y separar sus responsabilidades en servicios independientes, cada uno en su propia EC2. El alumno observa como cambian las rutas, los contratos, las dependencias y la observabilidad cuando una aplicacion se divide en servicios con infraestructura separada.

**Duracion estimada:** 2-3 horas

**Modulo:** Modulo 2 — Clase 3: Monolito a microservicios

---

## Contexto

Sorny es una tienda de televisores. El sitio permite ver seis modelos, seleccionar uno, comprarlo y dejar datos de contacto para coordinar el envio.

Hoy, todo el backend vive en un unico proceso. Cuando un cliente compra, ese proceso:

1. recibe la solicitud;
2. revisa si hay stock;
3. descuenta el inventario;
4. genera un enlace de pago;
5. registra los datos de envio del cliente.

Eso funciona, pero tiene un problema: las tres responsabilidades (compras, stock, pagos) estan mezcladas en el mismo codigo. En este laboratorio se divide ese backend en servicios independientes, **cada uno en su propia EC2**.

| Servicio | EC2 | Que hace |
|---|---|---|
| `frontend` | EC2-frontend | Muestra la tienda y gestiona el checkout |
| `monolithic-backend` | EC2-monolith | Responde catalogo, compras y delivery (monolito inicial) |
| `delivery-service` | EC2-monolith | Recibe datos de contacto para coordinar envio |
| `purchase-service` | EC2-services | Recibe la compra y coordina stock + pago |
| `stock-service` | EC2-services | Valida y reserva inventario |
| `payment-service` | EC2-services | Genera el enlace de pago |

Al dividir el backend aparecen preguntas nuevas:
- como se comunican servicios que estan en distintas EC2s;
- que pasa si un servicio responde mal o falla;
- donde miro logs cuando el flujo completo no funciona.

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
  +-- /api/stock/*        -> stock-service (EC2-services, puerto 5003)
  |
  +-- /api/payments/*     -> payment-service (EC2-services, puerto 5004)
  |
  +-- /api/*              -> monolith fallback (EC2-monolith, puerto 5001)
       (fallback para rutas no migradas)
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

> **¿Por que SSM en vez de SSH?** Session Manager permite conectarse a la EC2 desde la consola de AWS sin clave SSH ni IP publica. Durante el laboratorio se usa para inspeccionar servicios y corregir configuracion.

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
- 6 target groups (frontend, monolith, delivery, purchase, stock, payment)
- Reglas base del ALB (`/api/*` -> monolith, `/*` -> frontend)
- CloudWatch Log Group
- Alarmas de status check para cada EC2

> **¿Que aplicaciones levanta cada EC2?** El template instala Python, Flask y Gunicorn. Cada servicio tiene su propio codigo y corre como proceso systemd independiente. La EC2-frontend tiene solo el frontend. La EC2-monolith tiene el monolito (5001) y el servicio de delivery (5005). La EC2-services tiene purchase (5002), stock (5003) y payment (5004).

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
   - **PurchaseStockServiceUrl:** dejar default (`http://127.0.0.1:5999/api/stock`)
   - **PurchasePaymentServiceUrl:** dejar default (`http://127.0.0.1:5004/api/payments`)
   - **CreateBaseAlbRules:** `true`
   - **CreateMicroserviceAlbRules:** `false`
7. Click **Next** dos veces
8. Click **Submit**
9. Esperar a estado **CREATE_COMPLETE** (~8-10 minutos)

> **¿Por que CreateBaseAlbRules=true y CreateMicroserviceAlbRules=false?** Con `true`, el sitio arranca funcionando contra el monolito. Con `false`, los alumnos crean las reglas manualmente como parte del ejercicio.

> **¿Por que PurchaseStockServiceUrl apunta al puerto 5999?** Ese puerto no existe. Es intencional: cuando los alumnos activen las reglas de microservicios, `purchase-service` fallara al consultar stock. Esa falla se diagnostica con CloudWatch.

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
   - `StockTargetGroupArn` — ARN del TG stock
   - `PaymentTargetGroupArn` — ARN del TG payment
   - `BrokenPurchaseStockServiceUrl` — confirma la URL rota

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
2. Deberia aparecer un modal con "Procesando compra..."
3. Luego el modal muestra un formulario con campos: Nombre, Email, Telefono, Direccion de envio
4. Completar los datos y click en **Confirmar compra**
5. Deberia verse una pantalla de exito: "¡Compra procesada! Te vamos a contactar para coordinar el envio"

> **¿Que paso atras?** El frontend envio un POST a `/api/purchases`. El monolito (EC2-monolith, puerto 5001) recibio la solicitud, verifico stock, genero un ID de compra y devolvio un enlace. Luego el frontend mostro el formulario de checkout. Al confirmar, envio un POST a `/api/delivery` que el monolito tambien proceso. Todo paso por el mismo backend monolitico en una sola EC2.

### 2.3 Ver los endpoints del monolito

Probar directamente:

- `http://<AlbDnsName>/api/products` — lista de 6 modelos con `"backend": "monolithic-backend"`
- `http://<AlbDnsName>/api/health` — `{"service": "monolithic-backend", "status": "ok"}`

> **¿Por que aparece "monolithic-backend"?** Cada servicio responde con un campo `backend` que indica quien proceso la request. Cuando se separen las rutas, ese campo mostrara `purchase-service`, `stock-service` o `payment-service`.

---

## Fase 3: Inspeccionar los componentes en AWS

### 3.1 Ubicar los target groups

1. Ir a **EC2 > Target Groups**
2. Buscar los target groups que empiezan con `sorni-`
3. Identificar los 6 TGs:
   - `sorni-Front-*` (frontend, EC2-frontend, puerto 5000)
   - `sorni-Monol-*` (monolith, EC2-monolith, puerto 5001)
   - `sorni-Deliv-*` (delivery, EC2-monolith, puerto 5005)
   - `sorni-Purch-*` (purchase, EC2-services, puerto 5002)
   - `sorni-Stock-*` (stock, EC2-services, puerto 5003)
   - `sorni-Payme-*` (payment, EC2-services, puerto 5004)
4. Verificar estado:
   - `frontend` y `monolith` deben estar **healthy**
   - `delivery`, `purchase`, `stock`, `payment` pueden estar **unused** (sin reglas del ALB)

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
curl -s http://127.0.0.1:5003/api/stock/health
curl -s http://127.0.0.1:5004/api/payments/health
```

> **¿Por que entrar por Session Manager?** No requiere puertos abiertos ni claves SSH. La EC2 solo necesita el IAM Role con `AmazonSSMManagedInstanceCore`.

### 3.3 Revisar las reglas actuales del ALB

1. Ir a **EC2 > Load Balancers**
2. Seleccionar el ALB (`sorni-ms-*`)
3. Pestana **Listeners** > click en `HTTP :80` > **Rules**
4. Deberian verse:
   - **Priority 100:** `/api/*` -> monolith TG
   - **Priority 200:** `/*` -> frontend TG
   - **Default:** fixed-response 404

---

## Fase 4: Crear reglas path-based del ALB

El ALB decide a que target group enviar cada request segun la ruta. Vamos a separar el trafico hacia los servicios en EC2-services.

### 4.1 Crear regla para compras

1. Ir a **EC2 > Load Balancers** > ALB > **Listeners** > `HTTP :80` > **View/edit rules**
2. Click **Add rule**
3. Configurar:
   - **Priority:** `10`
   - **Condition > Path:** `/api/purchases`
   - **Additional path:** `/api/purchases/*`
   - **Action:** Forward to `sorni-Purch-*` (purchase-service)
4. Guardar

### 4.2 Crear regla para stock

1. Click **Add rule**
2. Configurar:
   - **Priority:** `20`
   - **Condition > Path:** `/api/stock`
   - **Additional path:** `/api/stock/*`
   - **Action:** Forward to `sorni-Stock-*`
3. Guardar

### 4.3 Crear regla para pagos

1. Click **Add rule**
2. Configurar:
   - **Priority:** `30`
   - **Condition > Path:** `/api/payments`
   - **Additional path:** `/api/payments/*`
   - **Action:** Forward to `sorni-Payme-*`
3. Guardar

### 4.4 Verificar el orden final

| Prioridad | Path | Target group | EC2 |
|---|---|---|---|
| 10 | `/api/purchases`, `/api/purchases/*` | purchase | EC2-services |
| 20 | `/api/stock`, `/api/stock/*` | stock | EC2-services |
| 30 | `/api/payments`, `/api/payments/*` | payment | EC2-services |
| 100 | `/api/*` | monolith | EC2-monolith |
| 200 | `/*` | frontend | EC2-frontend |
| default | (ninguna) | fixed-response 404 | — |

### 4.5 Verificar health

1. Ir a **EC2 > Target Groups**
2. `purchase`, `stock`, `payment` deben pasar de `unused` a **healthy**

---

## Fase 5: Probar el flujo con microservicios

1. Ir al sitio `http://<AlbDnsName>/`
2. Comprar un televisor

**Resultado esperado:** La compra falla. Muestra "stock_service_unavailable".

> **¿Por que falla si los target groups estan healthy?** `purchase-service` en EC2-services intenta consultar stock en `127.0.0.1:5999`, pero stock corre en `127.0.0.1:5003`. El puerto 5999 no existe. El servicio esta "vivo" pero tiene una dependencia mal configurada.

Probar los endpoints directamente:

- `http://<AlbDnsName>/api/stock/sorni-luma-32` — responde OK con `"backend": "stock-service"`
- `POST http://<AlbDnsName>/api/purchases` — falla con `stock_service_unavailable`

---

## Fase 6: Diagnosticar con CloudWatch

### 6.1 Revisar logs de purchase-service

1. Ir a **CloudWatch > Log groups > `/sorny/microservices-site/site`**
2. Abrir el log stream `purchase-service`
3. Buscar el error:

```
stock reservation failed sku=sorni-luma-32 stock_service_url=http://127.0.0.1:5999/api/stock
Connection refused
```

### 6.2 Confirmar que stock-service no recibio la llamada

1. En el mismo log group, abrir `stock-service`
2. No deberian verse registros de reserva para esa compra

### 6.3 Revisar metricas del ALB

1. Ir a **EC2 > Target Groups** > `sorni-Purch-*` > **Monitoring**
2. Revisar `HTTPCode_Target_5XX_Count` — debe haber picos de 503

---

## Fase 7: Corregir y validar

### 7.1 Entrar a la EC2-services por Session Manager

1. Ir a **EC2 > Instances**
2. Seleccionar `sorny-services-*` (usar `ServicesNodeId`)
3. **Connect > Session Manager > Connect**

### 7.2 Inspeccionar la configuracion actual

```bash
sudo systemctl cat sorni-purchase
```

Debe mostrar `STOCK_SERVICE_URL=http://127.0.0.1:5999/api/stock`.

### 7.3 Corregir la URL

```bash
sudo systemctl edit sorni-purchase
```

Agregar en el editor:

```
[Service]
Environment=STOCK_SERVICE_URL=http://127.0.0.1:5003/api/stock
```

Guardar y salir.

### 7.4 Recargar y reiniciar

```bash
sudo systemctl daemon-reload
sudo systemctl restart sorni-purchase
sudo systemctl status sorni-purchase --no-pager
```

### 7.5 Validar la correccion

```bash
sudo systemctl show sorni-purchase -p Environment
```

Debe mostrar `STOCK_SERVICE_URL=http://127.0.0.1:5003/api/stock`.

### 7.6 Probar la compra nuevamente

1. Volver al sitio
2. Comprar un televisor
3. Completar el formulario de contacto
4. La compra debe completarse exitosamente

La respuesta de la API ahora muestra `"backend": "purchase-service"`, confirmando que paso por el servicio separado en EC2-services.

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
- La compra monolitica funciona con formulario de contacto y pantalla de exito
- Los target groups de frontend y monolith estan healthy
- Los target groups de purchase, stock y payment pasan a healthy al crear reglas del ALB
- Sin las reglas, la compra falla con `stock_service_unavailable`
- Los logs de CloudWatch muestran el error de conexion a puerto 5999
- Corrigiendo `STOCK_SERVICE_URL` al puerto 5003, la compra funciona
- La respuesta de la API muestra `"backend": "purchase-service"` despues de la correccion
- Se puede explicar por que un servicio puede estar "healthy" pero el flujo completo falla