# Guia MS-01: Sorny — de monolito a microservicios en AWS

**Objetivo:** Partir de una aplicacion web funcional con un backend monolitico y separar sus responsabilidades en servicios independientes, cada uno en su propia EC2. El alumno observa como cambian las rutas, los contratos, las dependencias y la observabilidad cuando una aplicacion se divide en servicios con infraestructura separada.

**Duracion estimada:** 2-3 horas

**Modulo:** Modulo 2 — Clase 3: Monolito a microservicios

---

## Contexto

Sorny es una tienda de televisores. El sitio permite ver seis modelos, seleccionar uno, comprarlo y dejar datos de contacto para coordinar el envio.

Hoy, todo el backend vive en un unico proceso. Cuando un cliente compra, ese proceso recibe la solicitud, genera un enlace de pago y registra los datos de envio del cliente. Eso funciona, pero tiene un problema: compras, pagos y delivery estan mezclados en el mismo codigo.

En este laboratorio se divide ese backend en servicios independientes, **uno por EC2**.

| Servicio | EC2 | Puerto | Que hace |
|---|---|---|---|
| `frontend` | EC2-frontend | 5000 | Muestra la tienda y gestiona el checkout |
| `monolithic-backend` | EC2-monolith | 5001 | Catalogo, compras y delivery (monolito inicial) |
| `delivery-service` | EC2-delivery | 5005 | Recibe datos de contacto para coordinar envio |
| `purchase-service` | EC2-purchase | 5002 | Recibe la compra y coordina el pago |
| `payment-service` | EC2-payment | 5004 | Genera el enlace de pago |

Al dividir el backend aparecen preguntas nuevas:
- como decide el ALB a que servicio mandar cada request;
- como se comunican servicios que estan en EC2s distintas;
- que pasa cuando una dependencia entre servicios falla;
- donde miro logs cuando el flujo completo no funciona.

---

## Arquitectura inicial (solo con reglas base)

```
Usuario
  |
  v
ALB
  |
  +-- /            -> frontend   (EC2-frontend, puerto 5000)
  |
  +-- /api/*       -> monolith   (EC2-monolith, puerto 5001)
```

## Arquitectura final (con microservicios)

```
Usuario
  |
  v
ALB
  |
  +-- /                   -> frontend        (EC2-frontend,  puerto 5000)
  |
  +-- /api/purchases/*    -> purchase-service (EC2-purchase,  puerto 5002)
  |
  +-- /api/delivery/*     -> delivery-service (EC2-delivery,  puerto 5005)
  |
  +-- /api/payments/*     -> payment-service  (EC2-payment,   puerto 5004)
  |
  +-- /api/*              -> monolith fallback (EC2-monolith, puerto 5001)
       (fallback para rutas no migradas: /api/products, /api/health)
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
| IAM Instance Profile con `AmazonSSMManagedInstanceCore` y `CloudWatchAgentServerPolicy` | Debe existir |

> **¿Por que necesitamos dos subnets?** El ALB necesita al menos dos subnets en distintas AZs. Las EC2s van en SubnetA, el ALB ocupa ambas.

> **¿Por que SSM en vez de SSH?** Session Manager permite conectarse desde la consola sin clave SSH ni IP publica. Se usa para inspeccionar y corregir configuracion durante el lab.

### Anotar valores necesarios antes de desplegar

- **VpcId** — desde **VPC > Your VPCs**
- **SubnetAId** — subnet publica en `us-east-1a`
- **SubnetBId** — subnet publica en `us-east-1b`
- **SsmInstanceProfileName** — `cloudcuyo-ssm-role`

---

## Fase 1: Desplegar la infraestructura Sorny

El stack `cloudformation/microservices-sorny-stack.yaml` crea:

- 1 ALB publico con listener HTTP :80 (sin reglas — solo default 404)
- 6 Security Groups (ALB + uno por EC2)
- 5 EC2s con Amazon Linux 2023 (frontend, monolith, delivery, purchase, payment)
- 5 target groups (frontend, monolith, delivery, purchase, payment)
- CloudWatch Log Group con streams por servicio
- 5 alarmas de status check (una por EC2)

> **¿Por que el ALB arranca sin reglas?** Las reglas del ALB son el ejercicio principal del lab. El stack levanta toda la infraestructura pero deja el ALB vacio. El alumno construye la tabla de routing completa paso a paso.

> **¿Un servicio por EC2?** Si. Cada EC2 instala solo el codigo de su servicio. EC2-purchase tiene solo purchase-service. EC2-payment tiene solo payment-service. Esto hace visible la dependencia entre servicios: purchase necesita llamar a payment por red, no por localhost.

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
   - **PurchasePaymentServiceUrl:** dejar default (`http://REPLACE-WITH-ALB-DNS/api/payments`)
   - **CreateBaseAlbRules:** `false`
   - **CreateMicroserviceAlbRules:** `false`
   - **DeployMonolito:** `false`
7. Click **Next** dos veces
8. Click **Submit**
9. Esperar a estado **CREATE_COMPLETE** (~10-12 minutos)

> **¿Por que PurchasePaymentServiceUrl tiene un placeholder?** purchase-service necesita llamar a payment-service por red (estan en EC2s separadas). El DNS del ALB no se conoce antes del deploy. El alumno lo corregira en la Fase 7 una vez que tenga el DNS del stack.

> **DeployMonolito=true (modo instructor):** Crea automaticamente todas las reglas del ALB (base + microservicios). El alumno se salta las Fases 3 y 4 y arranca directo en la Fase 5 (diagnostico). `PAYMENT_SERVICE_URL` sigue siendo el placeholder — el ejercicio de diagnostico y fix con CloudWatch y `systemctl edit` es obligatorio igual.

### 1.2 Anotar outputs del stack

Cuando el stack llegue a **CREATE_COMPLETE**:

1. Ir a pestana **Outputs**
2. Anotar **todos** los valores — los vamos a usar en cada fase:

   | Output | Descripcion |
   |---|---|
   | `AlbDnsName` | DNS del ALB — anotar en un lugar visible |
   | `FrontendNodeId` | ID de EC2-frontend |
   | `MonolithNodeId` | ID de EC2-monolith |
   | `DeliveryNodeId` | ID de EC2-delivery |
   | `PurchaseNodeId` | ID de EC2-purchase |
   | `PaymentNodeId` | ID de EC2-payment |
   | `FrontendTargetGroupArn` | ARN del TG frontend |
   | `MonolithTargetGroupArn` | ARN del TG monolith |
   | `DeliveryTargetGroupArn` | ARN del TG delivery |
   | `PurchaseTargetGroupArn` | ARN del TG purchase |
   | `PaymentTargetGroupArn` | ARN del TG payment |

### Troubleshooting de la Fase 1

| Sintoma | Posible causa | Correccion |
|---|---|---|
| Stack en `CREATE_FAILED` | Parametro incorrecto (VPC, subnets) | Revisar eventos en CloudFormation > Events |
| Stack timeout | Subnet sin salida a internet | Verificar ruta `0.0.0.0/0 -> IGW` en la route table |
| Error de IAM | Instance Profile no existe | Verificar nombre en IAM > Instance Profiles |

---

## Fase 2: Inspeccionar los componentes

Con el stack desplegado, antes de crear cualquier regla, inspeccionamos lo que tenemos.

### 2.1 Verificar que el ALB esta vacio

1. Abrir el navegador en `http://<AlbDnsName>/`
2. Debe aparecer: `Sorny route not configured` con HTTP 404

Esto es esperado. El listener existe pero no tiene ninguna regla. Todo request cae en la default action.

3. Ir a **EC2 > Load Balancers** > seleccionar el ALB > pestana **Listeners and rules** > click en **HTTP:80**
4. Debe verse solo la **Default action**: fixed-response 404

### 2.2 Verificar los target groups

1. Ir a **EC2 > Target Groups**
2. Los 5 TGs deben aparecer con estado **unused**:

   | Target group | EC2 | Puerto |
   |---|---|---|
   | `sorni-Front-*` | EC2-frontend | 5000 |
   | `sorni-Monol-*` | EC2-monolith | 5001 |
   | `sorni-Deliv-*` | EC2-delivery | 5005 |
   | `sorni-Purch-*` | EC2-purchase | 5002 |
   | `sorni-Payme-*` | EC2-payment | 5004 |

3. Click en cualquier TG > pestana **Targets**
4. La instancia debe estar **healthy** — el servicio responde localmente aunque el ALB no le envie trafico todavia.

> **"unused" no es un error.** Los servicios estan vivos y sus health checks pasan. Solo falta que el ALB tenga reglas que los referencien.

### 2.3 Verificar las 5 EC2s via Session Manager

1. Ir a **EC2 > Instances** — deben verse 5 instancias running:
   - `sorny-frontend-*`
   - `sorny-monolith-*`
   - `sorny-delivery-*`
   - `sorny-purchase-*`
   - `sorny-payment-*`

2. Conectarse a cada una via **Connect > Session Manager** y verificar el servicio:

**EC2-frontend:**
```bash
curl -s http://127.0.0.1:5000/health
# {"service": "frontend", "status": "ok"}
```

**EC2-monolith:**
```bash
curl -s http://127.0.0.1:5001/api/health
# {"service": "monolithic-backend", "status": "ok"}
```

**EC2-delivery:**
```bash
curl -s http://127.0.0.1:5005/api/delivery/health
# {"service": "delivery-service", "status": "ok"}
```

**EC2-purchase:**
```bash
curl -s http://127.0.0.1:5002/api/purchases/health
# {"service": "purchase-service", "status": "ok", "payment_service_url": "http://REPLACE-WITH-ALB-DNS/api/payments"}
```

> Notar que `payment_service_url` muestra el placeholder. purchase-service todavia no sabe como llegar a payment-service. Esto se corrige en la Fase 6.

**EC2-payment:**
```bash
curl -s http://127.0.0.1:5004/api/payments/health
# {"service": "payment-service", "status": "ok"}
```

---

## Fase 3: Crear las reglas base del ALB

En esta fase conectamos el ALB con el frontend y el monolito. Al terminar, el sitio funciona completamente contra el backend monolitico.

### Como navegar al listener del ALB

Estos pasos aplican para crear cualquier regla en esta y en la siguiente fase:

1. Ir a **EC2 > Load Balancing > Load Balancers**
2. Click en el nombre del ALB (`sorny-ms-microservices-site` o similar)
3. Pestana **Listeners and rules** > click en el enlace **HTTP:80**

---

### 3.1 Crear regla para el frontend

1. Click en **Add rule**

**Step 1 — Rule details:**
- **Name:** `frontend-rule`
- Click **Next**

**Step 2 — Add conditions:**
- Click **Add condition** > **Path** > Value: `/*`
- Click **Confirm** > **Next**

**Step 3 — Define actions:**
- **Routing action:** Forward to target groups
- **Target group:** `sorni-Front-*` (puerto 5000)
- Click **Next**

**Step 4 — Set rule priority:**
- **Priority:** `200` > **Next**

Click **Create**.

---

### 3.2 Crear regla para el monolito

1. Click en **Add rule**

**Step 1 — Rule details:**
- **Name:** `monolith-api-rule`
- Click **Next**

**Step 2 — Add conditions:**
- Click **Add condition** > **Path** > Value: `/api/*`
- Click **Confirm** > **Next**

**Step 3 — Define actions:**
- **Target group:** `sorni-Monol-*` (puerto 5001)
- Click **Next**

**Step 4 — Set rule priority:**
- **Priority:** `100` > **Next**

Click **Create**.

---

### 3.3 Verificar el orden y probar el sitio

La lista debe quedar:

| Prioridad | Path | Target group | EC2 |
|---|---|---|---|
| 100 | `/api/*` | sorni-Monol-* | EC2-monolith (5001) |
| 200 | `/*` | sorni-Front-* | EC2-frontend (5000) |
| default | — | fixed-response 404 | — |

Esperar 1-2 minutos a que `sorni-Front-*` y `sorni-Monol-*` pasen a **healthy**, luego:

1. Abrir `http://<AlbDnsName>/` — deben verse los 6 televisores
2. Probar la compra completa — debe completarse exitosamente
3. `http://<AlbDnsName>/api/products` → `"backend": "monolithic-backend"` ✓
4. `http://<AlbDnsName>/api/health` → `{"service": "monolithic-backend", ...}` ✓

> El flujo completo pasa por EC2-monolith. El campo `"backend"` en las respuestas confirma quien proceso cada request.

---

## Fase 4: Crear las reglas de microservicios

Ahora agregamos reglas mas especificas para desviar compras, delivery y pagos a sus EC2s dedicadas. Al tener numeros de prioridad mas bajos (10, 20, 30), se evaluan antes que la regla `/api/*` (100) y la capturan primero.

### 4.1 Crear regla para purchase-service

1. Click en **Add rule**

**Step 1 — Rule details:**
- **Name:** `purchase-service-rule` > **Next**

**Step 2 — Add conditions:**
- Click **Add condition** > **Path**
- Value 1: `/api/purchases`
- Click **Add new value** > Value 2: `/api/purchases/*`
- Click **Confirm** > **Next**

**Step 3 — Define actions:**
- **Target group:** `sorni-Purch-*` (puerto 5002) > **Next**

**Step 4 — Set rule priority:**
- **Priority:** `10` > **Next**

Click **Create**.

---

### 4.2 Crear regla para delivery-service

1. Click en **Add rule**

**Step 1 — Rule details:**
- **Name:** `delivery-service-rule` > **Next**

**Step 2 — Add conditions:**
- Click **Add condition** > **Path**
- Value 1: `/api/delivery`
- Click **Add new value** > Value 2: `/api/delivery/*`
- Click **Confirm** > **Next**

**Step 3 — Define actions:**
- **Target group:** `sorni-Deliv-*` (puerto 5005) > **Next**

**Step 4 — Set rule priority:**
- **Priority:** `20` > **Next**

Click **Create**.

---

### 4.3 Crear regla para payment-service

1. Click en **Add rule**

**Step 1 — Rule details:**
- **Name:** `payment-service-rule` > **Next**

**Step 2 — Add conditions:**
- Click **Add condition** > **Path**
- Value 1: `/api/payments`
- Click **Add new value** > Value 2: `/api/payments/*`
- Click **Confirm** > **Next**

**Step 3 — Define actions:**
- **Target group:** `sorni-Payme-*` (puerto 5004) > **Next**

**Step 4 — Set rule priority:**
- **Priority:** `30` > **Next**

Click **Create**.

---

### 4.4 Verificar el orden final de todas las reglas

| Prioridad | Condicion de path | Target group | EC2 |
|---|---|---|---|
| 10 | `/api/purchases` o `/api/purchases/*` | sorni-Purch-* | EC2-purchase (5002) |
| 20 | `/api/delivery` o `/api/delivery/*` | sorni-Deliv-* | EC2-delivery (5005) |
| 30 | `/api/payments` o `/api/payments/*` | sorni-Payme-* | EC2-payment (5004) |
| 100 | `/api/*` | sorni-Monol-* | EC2-monolith (5001) |
| 200 | `/*` | sorni-Front-* | EC2-frontend (5000) |
| default | — | fixed-response 404 | — |

Esperar 1-2 minutos a que `sorni-Purch-*`, `sorni-Deliv-*` y `sorni-Payme-*` pasen a **healthy**.

---

## Fase 5: Probar el flujo con microservicios

### 5.1 Probar la compra

1. Ir al sitio `http://<AlbDnsName>/`
2. Click en **Comprar ahora** en cualquier televisor

**Resultado esperado:** La compra **falla**. El modal muestra un error: "No pudimos completar la compra: payment_service_unavailable".

### 5.2 Entender por que falla

Los target groups estan healthy. El ALB envia el request a EC2-purchase. Pero purchase-service necesita llamar a payment-service para generar el enlace de pago, y no sabe como encontrarlo.

Probar el endpoint directamente:

```
POST http://<AlbDnsName>/api/purchases
Content-Type: application/json

{"sku": "sorni-luma-32", "customer": "test@sorny.local"}
```

Respuesta:
```json
{"error": "payment_service_unavailable", "detail": "...REPLACE-WITH-ALB-DNS..."}
```

> **¿Por que falla si payment-service esta healthy?** payment-service esta vivo y responde en EC2-payment. Pero purchase-service no sabe su direccion. Intenta conectarse a `http://REPLACE-WITH-ALB-DNS/api/payments` — un hostname que no existe. El health check del ALB verifica que el servicio responde en su puerto, no que sus dependencias esten configuradas correctamente.

> **Esta es la diferencia clave con el monolito.** En el monolito, purchase y payment vivian en el mismo proceso. No habia red de por medio. Al separarlos en EC2s distintas, aparece la necesidad de service discovery o configuracion explicita de URLs.

---

## Fase 6: Diagnosticar con CloudWatch

### 6.1 Ver los logs de purchase-service

1. Ir a **CloudWatch > Log groups**
2. Abrir `/sorny/microservices-site/site`
3. Click en el stream `purchase-service`
4. Buscar la entrada del intento de compra fallido:

```
purchase sku=sorni-luma-32 customer=test@sorny.local
payment fail pid=pur-abc12345 url=http://REPLACE-WITH-ALB-DNS/api/payments
...Failed to establish a new connection: [Errno -3] Temporary failure in name resolution
```

El log muestra exactamente que sucedio: purchase-service intento conectarse al hostname `REPLACE-WITH-ALB-DNS` y no pudo resolverlo.

### 6.2 Confirmar que payment-service no recibio la llamada

1. En el mismo log group, abrir el stream `payment-service`
2. No debe haber registros de esa compra — la llamada nunca llego a payment-service

### 6.3 Identificar la correccion necesaria

El problema es claro: `PAYMENT_SERVICE_URL` en EC2-purchase apunta a un placeholder. Debe apuntar al ALB, que tiene la regla `/api/payments/*` → EC2-payment.

La URL correcta es: `http://<AlbDnsName>/api/payments`

El valor de `AlbDnsName` esta en los outputs del stack de la Fase 1.

---

## Fase 7: Corregir la URL de payment-service

### 7.1 Conectarse a EC2-purchase por Session Manager

1. Ir a **EC2 > Instances**
2. Seleccionar `sorny-purchase-*` (usar `PurchaseNodeId`)
3. Click **Connect > Session Manager > Connect**

### 7.2 Verificar la configuracion actual

```bash
sudo systemctl cat sorni-purchase
```

En la seccion `[Service]` debe verse:
```
Environment=PAYMENT_SERVICE_URL=http://REPLACE-WITH-ALB-DNS/api/payments
```

### 7.3 Editar el servicio con la URL correcta

```bash
sudo systemctl edit sorni-purchase
```

Se abre un editor. Agregar el siguiente contenido (reemplazar `<AlbDnsName>` con el valor del output):

```ini
[Service]
Environment=PAYMENT_SERVICE_URL=http://<AlbDnsName>/api/payments
```

Guardar y salir (Ctrl+X en nano, o `:wq` en vi).

### 7.4 Aplicar el cambio y reiniciar

```bash
sudo systemctl daemon-reload
sudo systemctl restart sorni-purchase
sudo systemctl status sorni-purchase --no-pager
```

### 7.5 Verificar la nueva configuracion

```bash
curl -s http://127.0.0.1:5002/api/purchases/health
```

El campo `payment_service_url` debe mostrar el DNS del ALB, no el placeholder.

### 7.6 Probar la compra nuevamente

1. Volver al sitio `http://<AlbDnsName>/`
2. Comprar un televisor y completar el formulario
3. La compra debe completarse exitosamente

### 7.7 Confirmar el flujo por microservicios

```
POST http://<AlbDnsName>/api/purchases
Content-Type: application/json

{"sku": "sorni-luma-32", "customer": "test@sorny.local"}
```

La respuesta debe incluir `"backend": "purchase-service"`.

Revisar en CloudWatch los streams `purchase-service` y `payment-service` — ambos deben tener registros del mismo `pid`.

---

## Fase 8: Observar con CloudWatch

### 8.1 Comparar los streams de una compra exitosa

1. Ir a **CloudWatch > Log groups > `/sorny/microservices-site/site`**
2. Abrir `purchase-service`:
   ```
   purchase sku=sorni-luma-32 customer=test@sorny.local
   purchase created pid=pur-abc12345 sku=sorni-luma-32
   ```
3. Abrir `payment-service`:
   ```
   payment link pid=pur-abc12345 amt=189999
   ```
4. Abrir `delivery-service` — debe tener el registro del POST a `/api/delivery` con nombre y email
5. Abrir `monolithic-backend` — no debe tener registros de esta compra

### 8.2 Comparar request counts por target group

1. **EC2 > Target Groups** > `sorni-Purch-*` > **Monitoring** > `RequestCount` — picos por cada compra
2. `sorni-Monol-*` > **Monitoring** — solo requests a `/api/products` y `/api/health`

> **¿Que demuestra esto?** Cada servicio tiene su propio scope. Los logs estan separados. Las metricas son por servicio. Si hay un error, se identifica en que parte del flujo ocurrio sin revisar un log gigante mezclado.

---

## Limpieza

1. Ir a **CloudFormation > Stacks**
2. Seleccionar `sorny-microservices-stack`
3. Click **Delete** > confirmar
4. Esperar ~5 minutos

**NO eliminar:** VPC, subnets, Internet Gateway, route tables, IAM roles.

---

## Criterios de exito

- El sitio devuelve 404 al abrir por primera vez (ALB sin reglas)
- Los 5 target groups aparecen como `unused` antes de crear reglas
- Los 5 servicios responden a `curl` por localhost en sus EC2s
- Despues de crear las reglas base, el sitio muestra los 6 televisores y la compra funciona via monolito
- Los TGs de purchase, delivery y payment pasan a healthy al crear las reglas de microservicios
- La primera compra con microservicios activos **falla** con `payment_service_unavailable`
- CloudWatch muestra el error en el stream `purchase-service` con la URL del placeholder
- El stream `payment-service` no tiene registros del intento fallido
- Despues de corregir `PAYMENT_SERVICE_URL` con `systemctl edit`, la compra funciona
- `POST /api/purchases` devuelve `"backend": "purchase-service"`
- Los streams de CloudWatch de purchase-service y payment-service tienen el mismo `pid`
- Se puede explicar por que un servicio puede estar "healthy" pero el flujo falla por una dependencia mal configurada
- Se puede explicar la diferencia entre health check de red y configuracion correcta de dependencias
