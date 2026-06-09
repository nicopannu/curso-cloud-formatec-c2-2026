# Guia MS-01: Sorny — de monolito a microservicios en AWS

**Objetivo:** Partir de una aplicacion web funcional con un backend monolitico y separar sus responsabilidades en servicios independientes, cada uno en su propia EC2. Vas a observar como cambian las rutas, las dependencias y la observabilidad cuando una aplicacion se divide en servicios con infraestructura separada.

**Duracion estimada:** 2-3 horas

**Modulo:** Modulo 2 — Clase 3: Monolito a microservicios

---

## Contexto

Sorny es una tienda de televisores. El sitio permite ver seis modelos, seleccionar uno, comprarlo y dejar datos de contacto para coordinar el envio.

Hoy, todo el backend vive en un unico proceso. Cuando un cliente compra, ese proceso recibe la solicitud, genera un enlace de pago y registra los datos de envio. Eso funciona, pero tiene un problema: compras, pagos y delivery estan mezclados en el mismo codigo.

En este laboratorio se divide ese backend en servicios independientes, **uno por EC2**.

| Servicio | EC2 | Puerto | Que hace |
|---|---|---|---|
| `frontend` | EC2-frontend | 5000 | Muestra la tienda y gestiona el checkout |
| `monolithic-backend` | EC2-monolith | 5001 | Catalogo, compras y delivery (monolito inicial) |
| `delivery-service` | EC2-delivery | 5005 | Recibe datos de contacto para coordinar envio |
| `purchase-service` | EC2-purchase | 5002 | Recibe la compra y coordina el pago |
| `payment-service` | EC2-payment | 5004 | Genera el enlace de pago |

Al separar los servicios van a aparecer preguntas concretas:
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
  +-- /                   -> frontend         (EC2-frontend,  puerto 5000)
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
- Permisos para EC2, CloudFormation, CloudWatch y ELB

### Recursos de red necesarios

| Recurso | Descripcion |
|---|---|
| VPC con Internet Gateway | Debe existir en la cuenta |
| Subnet publica en us-east-1a | Debe existir |
| Subnet publica en us-east-1b | Debe existir |
| IAM Instance Profile con permisos SSM y CloudWatch | Debe existir |

> **¿Por que dos subnets?** El ALB requiere al menos dos subnets en distintas zonas de disponibilidad. Las EC2s van en una, el ALB ocupa ambas.

> **¿Por que SSM en vez de SSH?** Session Manager permite conectarse a una EC2 desde la consola de AWS sin necesidad de clave SSH ni IP publica. Lo vamos a usar en la Fase 7 para corregir una configuracion.

### Anotar valores necesarios antes de desplegar

- **VpcId** — desde **VPC > Your VPCs**
- **SubnetAId** — subnet publica en `us-east-1a`
- **SubnetBId** — subnet publica en `us-east-1b`
- **SsmInstanceProfileName** — `cloudcuyo-ssm-role`

---

## Fase 1: Desplegar la infraestructura Sorny

El stack `cloudformation/microservices-sorny-stack.yaml` crea:

- 1 ALB publico con listener HTTP :80
- 6 Security Groups (ALB + uno por EC2)
- 5 EC2s con Amazon Linux 2023 (frontend, monolith, delivery, purchase, payment)
- 5 target groups (frontend, monolith, delivery, purchase, payment)
- CloudWatch Log Group con streams por servicio
- 5 alarmas de status check

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

> **Sobre el parametro DeployMonolito:** Si lo seteás en `true`, las reglas base del ALB (frontend y monolito) se crean automaticamente al terminar el deploy. El sitio Sorny va a funcionar con el monolito desde el primer momento. Arrancas directo en la Fase 4 para crear las reglas de microservicios, probar la compra y diagnosticar el error.

> **Sobre PurchasePaymentServiceUrl:** purchase-service necesita la direccion de payment-service para funcionar. Como aun no conocemos el DNS del ALB en este momento, el campo queda con un placeholder. Lo vas a corregir en la Fase 7 una vez que el stack este desplegado.

### 1.2 Anotar outputs del stack

Cuando el stack llegue a **CREATE_COMPLETE**:

1. Ir a pestana **Outputs**
2. Anotar los siguientes valores:

   | Output | Descripcion |
   |---|---|
   | `AlbDnsName` | DNS del ALB — lo vas a usar en todas las fases siguientes |
   | `PurchaseNodeId` | ID de EC2-purchase — lo vas a usar en la Fase 7 |
   | `FrontendNodeId` | ID de EC2-frontend |
   | `MonolithNodeId` | ID de EC2-monolith |
   | `DeliveryNodeId` | ID de EC2-delivery |
   | `PaymentNodeId` | ID de EC2-payment |

### Troubleshooting de la Fase 1

| Sintoma | Posible causa | Correccion |
|---|---|---|
| Stack en `CREATE_FAILED` | Parametro incorrecto (VPC, subnets) | Revisar eventos en CloudFormation > Events |
| Stack timeout | Subnet sin salida a internet | Verificar ruta `0.0.0.0/0 -> IGW` en la route table |
| Error de IAM | Instance Profile no existe | Verificar nombre en IAM > Instance Profiles |

---

## Fase 2: Inspeccionar los componentes

### 2.1 Verificar que el ALB esta vacio

1. Abrir el navegador en `http://<AlbDnsName>/`
2. Debe aparecer: `Sorny route not configured` con HTTP 404

El ALB existe y el listener esta activo, pero todavia no tiene ninguna regla de routing. Todo request cae en la accion por defecto (404). Lo que ves en el navegador es exactamente lo esperado antes de configurar las rutas.

3. Ir a **EC2 > Load Balancers** > seleccionar el ALB (`sorni-ms-*`) > pestana **Listeners and rules** > click en **HTTP:80**
4. Debe verse solo la **Default action**: fixed-response 404

### 2.2 Verificar los target groups

1. Ir a **EC2 > Target Groups**
2. Los 5 TGs deben aparecer con estado **unused**:

   | Target group | Puerto | Servicio |
   |---|---|---|
   | `sorni-Front-*` | 5000 | frontend |
   | `sorni-Monol-*` | 5001 | monolithic-backend |
   | `sorni-Deliv-*` | 5005 | delivery-service |
   | `sorni-Purch-*` | 5002 | purchase-service |
   | `sorni-Payme-*` | 5004 | payment-service |

3. Click en cualquier TG > pestana **Targets**
4. La instancia debe estar **healthy**

> **"unused" no significa que el servicio este caido.** Significa que el TG existe y su instancia responde correctamente, pero el ALB todavia no tiene ninguna regla que le envie trafico. En cuanto creemos las reglas en las proximas fases, el estado va a cambiar.

---

## Fase 3: Crear las reglas base del ALB

En esta fase conectamos el ALB con el frontend y el monolito. Al terminar, el sitio va a funcionar completamente contra el backend monolitico.

### Como navegar al listener del ALB

Estos pasos son los mismos para cualquier regla que crees en esta fase y en la siguiente:

1. Ir a **EC2 > Load Balancing > Load Balancers**
2. Click en el nombre del ALB (`sorni-ms-microservices-site` o similar)
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

La lista de reglas debe quedar:

| Prioridad | Path | Target group | EC2 |
|---|---|---|---|
| 100 | `/api/*` | sorni-Monol-* | EC2-monolith (5001) |
| 200 | `/*` | sorni-Front-* | EC2-frontend (5000) |
| default | — | fixed-response 404 | — |

> El ALB evalua las reglas de menor a mayor numero. La regla 100 captura las APIs antes de que lleguen a la 200. Si el orden fuera al reves, el `/*` captaria todo antes que el `/api/*`.

Esperar 1-2 minutos a que `sorni-Front-*` y `sorni-Monol-*` pasen a **healthy**, luego:

1. Abrir `http://<AlbDnsName>/` — deben verse los 6 televisores Sorny
2. Click en **Comprar ahora** en cualquier televisor y completar la compra — debe completarse exitosamente
3. `http://<AlbDnsName>/api/products` → responde con `"backend": "monolithic-backend"`
4. `http://<AlbDnsName>/api/health` → responde con `{"service": "monolithic-backend", ...}`

El campo `"backend"` en las respuestas confirma que todo el flujo paso por EC2-monolith.

---

## Fase 4: Crear las reglas de microservicios

Ahora agregamos reglas mas especificas para desviar compras, delivery y pagos a sus EC2s dedicadas. Al tener numeros de prioridad menores (10, 20, 30), se evaluan antes que la regla `/api/*` (100) y la capturan primero.

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

**Resultado esperado:** La compra **falla**. El modal muestra: "No pudimos completar la compra: payment_service_unavailable".

### 5.2 Entender por que falla

Los target groups estan healthy y el ALB envia el request correctamente a EC2-purchase. El problema esta en otro lado: purchase-service necesita llamar a payment-service para generar el enlace de pago, y no sabe como llegar a el.

Podes confirmar esto probando el endpoint directamente:

```
POST http://<AlbDnsName>/api/purchases
Content-Type: application/json

{"sku": "sorni-luma-32", "customer": "test@sorny.local"}
```

La respuesta va a ser:
```json
{"error": "payment_service_unavailable", "detail": "...REPLACE-WITH-ALB-DNS..."}
```

El error incluye la URL que intento usar: `http://REPLACE-WITH-ALB-DNS/api/payments` — un hostname que no existe.

> **¿Por que falla si payment-service esta healthy?** El health check del ALB solo verifica que el servicio responde en su puerto. No sabe si las dependencias de ese servicio estan bien configuradas. payment-service esta vivo en EC2-payment, pero purchase-service no tiene su direccion correcta. Este es uno de los problemas caracteristicos de las arquitecturas distribuidas: un servicio puede estar "verde" y aun asi el flujo completo falla.

> **La diferencia con el monolito:** en el monolito, purchase y payment vivian en el mismo proceso. No habia red de por medio. Al separarlos en EC2s distintas, la URL de un servicio hacia el otro tiene que estar configurada explicitamente.

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

El log muestra exactamente que paso: purchase-service intento conectarse al hostname `REPLACE-WITH-ALB-DNS` y no pudo resolverlo en DNS.

### 6.2 Confirmar que payment-service no recibio la llamada

1. En el mismo log group, abrir el stream `payment-service`
2. No hay registros de esa compra — la llamada nunca llego a payment-service

### 6.3 Identificar la correccion

La URL correcta de payment-service es `http://<AlbDnsName>/api/payments`. El ALB ya tiene la regla `/api/payments/*` → EC2-payment. Solo falta que purchase-service use esa URL.

---

## Fase 7: Corregir la URL de payment-service

### 7.1 Conectarse a EC2-purchase por Session Manager

1. Ir a **EC2 > Instances**
2. Buscar la instancia con ID `<PurchaseNodeId>` (del output del stack)
3. Click en **Connect > Session Manager > Connect**

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

Se abre un editor. Ingresar el siguiente contenido reemplazando `<AlbDnsName>` con el valor del output:

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

### 7.6 Probar la compra

1. Volver al sitio `http://<AlbDnsName>/`
2. Comprar un televisor y completar el formulario
3. La compra debe completarse exitosamente

La respuesta de la API ahora incluye `"backend": "purchase-service"`, confirmando que el request paso por EC2-purchase y no por el monolito.

---

## Fase 8: Observar con CloudWatch

### 8.1 Seguir el flujo de una compra exitosa en los logs

1. Ir a **CloudWatch > Log groups > `/sorny/microservices-site/site`**
2. Abrir el stream `purchase-service`:
   ```
   purchase sku=sorni-luma-32 customer=test@sorny.local
   purchase created pid=pur-abc12345 sku=sorni-luma-32
   ```
3. Abrir el stream `payment-service`:
   ```
   payment link pid=pur-abc12345 amt=189999
   ```
4. Abrir el stream `delivery-service` — debe tener el registro con nombre y email del cliente
5. Abrir el stream `monolithic-backend` — no debe tener registros de esta compra

Cada servicio tiene su propio stream de logs. Para diagnosticar un problema, no hay que buscar en un log mezclado: se abre el stream del servicio que fallo.

### 8.2 Comparar metricas por target group

1. Ir a **EC2 > Target Groups** > `sorni-Purch-*` > pestana **Monitoring**
2. Revisar `RequestCount` — muestra los picos correspondientes a las compras
3. Ir a `sorni-Monol-*` > **Monitoring**
4. Su `RequestCount` refleja solo las rutas que no fueron migradas: `/api/products`, `/api/health`

El monolito sigue activo como fallback para las rutas no migradas. Esto permite hacer la migracion de forma gradual, servicio por servicio, sin necesidad de migrar todo al mismo tiempo.

---

## Limpieza

1. Ir a **CloudFormation > Stacks**
2. Seleccionar `sorny-microservices-stack`
3. Click **Delete** > confirmar
4. Esperar ~5 minutos hasta que desaparezca

**No eliminar:** VPC, subnets, Internet Gateway, route tables, IAM roles.

---

## Criterios de exito

- El sitio devuelve 404 al abrir por primera vez (ALB sin reglas)
- Los 5 target groups aparecen como `unused` antes de crear reglas
- Despues de crear las reglas base, el sitio muestra los 6 televisores y la compra funciona via monolito
- Los TGs de purchase, delivery y payment pasan a **healthy** al crear las reglas de microservicios
- La primera compra con microservicios activos **falla** con `payment_service_unavailable`
- Los logs de CloudWatch muestran el error en el stream `purchase-service`
- El stream `payment-service` no tiene registros del intento fallido
- Despues de corregir `PAYMENT_SERVICE_URL` con `systemctl edit`, la compra funciona
- `POST /api/purchases` devuelve `"backend": "purchase-service"`
- Los streams `purchase-service` y `payment-service` tienen registros del mismo `pid`
- Se puede explicar por que un servicio puede estar "healthy" pero el flujo completo falla por una dependencia mal configurada
