# Guia MS-02: Sorny — de monolito a microservicios en AWS

**Objetivo:** Partir de una aplicacion web funcional con un backend monolitico y separar sus responsabilidades en servicios independientes. El alumno observa como cambian las rutas, los contratos, las dependencias y la observabilidad cuando una aplicacion se divide.

**Duracion estimada:** 2-3 horas

**Modulo:** Modulo 2 — Clase 3: Monolito a microservicios

---

## Contexto

Sorny es una tienda de televisores. El sitio permite ver seis modelos, seleccionar uno y comprarlo.

Hoy, todo el backend vive en un unico proceso. Cuando un cliente compra, ese proceso:

1. recibe la solicitud;
2. revisa si hay stock;
3. descuenta el inventario;
4. genera un enlace de pago;
5. devuelve todo junto al frontend.

Eso funciona. Pero tiene un problema: las tres cosas que hace (compras, stock, pagos) estan mezcladas en el mismo codigo. Si el equipo de pagos quiere cambiar algo, toca todo. Si stock tiene un error, no queda claro si es problema de stock, de compras o del enlace de pago.

En este laboratorio se divide ese backend en tres servicios chicos con responsabilidades claras:

| Servicio | Que hace |
|---|---|
| `purchase-service` | Recibe la compra y coordina el flujo |
| `stock-service` | Valida y reserva inventario |
| `payment-service` | Genera el enlace de pago |

Cada servicio vive como proceso separado en la misma EC2, cada uno con su puerto, su health check y su target group. Mas adelante, cada uno podria estar en servidores distintos.

Al dividir el backend aparecen preguntas nuevas:
- que servicio recibe la compra;
- que servicio es dueno del inventario;
- que servicio genera el enlace de pago;
- como se comunican entre si;
- que pasa si uno responde mal o falla;
- donde miro logs cuando el flujo completo no funciona.

La idea es ver esa complejidad con las manos, no solo pensarla.

---

## Arquitectura inicial

```
Usuario
  |
  v
ALB
  |
  +-- /       -> frontend (puerto 5000)
  |
  +-- /api/*  -> backend monolitico (puerto 5001)
```

## Arquitectura final esperada

```
Usuario
  |
  v
ALB
  |
  +-- /                   -> frontend
  |
  +-- /api/purchases/*    -> purchase-service (puerto 5002)
  |
  +-- /api/stock/*        -> stock-service (puerto 5003)
  |
  +-- /api/payments/*     -> payment-service (puerto 5004)
  |
  +-- /api/*              -> monolith fallback (puerto 5001)
       (fallback para rutas no migradas)

purchase-service
  |
  +-- consulta stock-service (para validar inventario)
  |
  +-- solicita enlace de pago a payment-service
```

---

## Pre-requisitos

### Herramientas y acceso

- Acceder a [https://console.aws.amazon.com/](https://console.aws.amazon.com/)
- Region: **us-east-1 (N. Virginia)**
- Permisos para EC2, CloudFormation, CloudWatch e IAM

### Recursos de red necesarios

Este laboratorio necesita una VPC con al menos una subnet publica, un ALB existente y un Instance Profile con SSM. Si la cuenta ya tiene estos recursos creados de laboratorios anteriores, usarlos.

**Recursos requeridos antes de comenzar:**

| Recurso | Descripcion |
|---|---|
| VPC con Internet Gateway | Ya debe existir en la cuenta |
| Subnet publica en us-east-1a | Ya debe existir |
| IAM Role con `AmazonSSMManagedInstanceCore` + `CloudWatchAgentServerPolicy` | Ya debe existir o se crea en el pre-requisito |

> **¿Por que necesitamos SSM en la EC2?** SSM (Systems Manager) permite conectarse a la instancia desde la consola de AWS sin clave SSH ni IP publica. Durante el laboratorio se usa para inspeccionar servicios y corregir configuracion. Es mas seguro que tener puertos SSH abiertos.

---

### Pre-req A: Verificar o crear ALB, Security Group e Instance Profile

Para este laboratorio se necesita un ALB publico con un listener HTTP en puerto 80, y un Instance Profile que permita SSM + CloudWatch en la EC2.

**Si no existen, desplegar el template auxiliar:**

1. Ir a **CloudFormation > Create stack > With new resources (standard)**
2. **Template source:** Upload a template file
3. Seleccionar `cloudformation/microservices-lab-prereqs.yaml` del repositorio
4. Click **Next**
5. **Stack name:** `sorny-microservices-prereqs`
6. **Parametros:**
   - **VpcId:** pegar el ID de la VPC del laboratorio
   - **PublicSubnetAId:** pegar el ID de la subnet publica en us-east-1a
   - **PublicSubnetBId:** pegar el ID de una subnet publica en us-east-1b
   - **ProjectName:** dejar `sorny`
   - **Environment:** dejar `microservices`
7. Click **Next** dos veces
8. En **Capabilities**, marcar **I acknowledge that AWS CloudFormation might create IAM resources**
9. Click **Submit**
10. Esperar a estado **CREATE_COMPLETE** (~2 minutos)
11. Ir a pestana **Outputs** y anotar:
    - `AlbDnsName` (DNS del ALB)
    - `AlbSecurityGroupId` (SG del ALB)
    - `AlbListenerArn` (ARN del listener HTTP :80)
    - `SsmInstanceProfileName` (nombre del Instance Profile)

> **¿Por que este template separado?** El stack principal (site-bootstrap) necesita un ALB, un listener y un Instance Profile que ya existan. Separar los prerequisitos permite que estos recursos se creen una vez y se reutilicen si se destruye y recrea el sitio. Tambien evita crear roles IAM cada vez que se prueba el laboratorio.

---

### Pre-req B: Anotar parametros para el stack principal

Antes de desplegar el sitio, tener a mano:

- **VpcId** — desde **VPC > Your VPCs**
- **SubnetId** — ID de la subnet publica en us-east-1a
- **AlbSgId** — desde Outputs del prereqs (o el SG existente del ALB)
- **AlbListenerArn** — desde Outputs del prereqs (o ARN del listener HTTP :80 existente)
- **SsmInstanceProfile** — desde Outputs del prereqs (o nombre del Instance Profile existente)

---

## Fase 1: Desplegar el sitio Sorny

El stack `cloudformation/microservices-site-bootstrap.yaml` crea:

- 1 EC2 con Amazon Linux 2023
- 5 aplicaciones como procesos systemd separados (cada uno en su puerto)
- 5 target groups (uno por servicio)
- Reglas base del ALB (`/api/*` -> monolith, `/*` -> frontend)
- CloudWatch Log Group
- Alarma base de status check EC2

> **¿Que aplicaciones levanta?** El template instala Python, Flask y Gunicorn en la EC2. Luego copia cinco aplicaciones en `/opt/sorni/` y las arranca como servicios systemd. Cada app vive en su propio puerto: frontend en 5000, monolith en 5001, purchase en 5002, stock en 5003, payment en 5004.

### 1.1 Desplegar con CloudFormation (AWS Console)

1. Ir a **CloudFormation > Create stack > With new resources (standard)**
2. **Template source:** Upload a template file
3. Seleccionar `cloudformation/microservices-site-bootstrap.yaml`
4. Click **Next**
5. **Stack name:** `sorny-microservices-site-bootstrap`
6. **Parametros — Grupo "Red y ALB existente":**
   - **VpcId:** pegar el VpcId
   - **SubnetId:** pegar la subnet publica us-east-1a
   - **AlbSgId:** pegar el SG ID del ALB
   - **AlbListenerArn:** pegar el ARN del listener HTTP :80
   - **CreateBaseAlbRules:** `true`
   - **CreateMicroserviceAlbRules:** `false`
7. **Parametros — Grupo "EC2":**
   - **InstanceType:** `t3.micro`
   - **SsmInstanceProfile:** pegar el nombre del Instance Profile
   - **LatestAmiId:** dejar el valor default
8. **Parametros — Grupo "Aplicacion":**
   - **PurchaseStockServiceUrl:** dejar el default (`http://127.0.0.1:5999/api/stock`)
   - **PurchasePaymentServiceUrl:** dejar el default (`http://127.0.0.1:5004/api/payments`)
   - **ProjectName:** `sorny`
   - **Environment:** `microservices-site`
9. Click **Next** dos veces
10. **Capabilities:** como el stack no crea recursos IAM, no es necesario marcar capacidades. Continuar directo.
11. Click **Submit**
12. Esperar a estado **CREATE_COMPLETE** (~5-7 minutos)

> **¿Por que CreateBaseAlbRules=true y CreateMicroserviceAlbRules=false?** Con CreateBaseAlbRules=true el sitio queda funcionando contra el monolito de entrada. Los alumnos pueden navegar y comprar. CreateMicroserviceAlbRules=false deja que los alumnos creen las reglas del ALB manualmente como parte del ejercicio.

> **¿Por que PurchaseStockServiceUrl apunta al puerto 5999?** Ese puerto no existe en la EC2. Es intencional. `purchase-service` intentara consultar stock en un puerto incorrecto, fallara, y esa falla sera diagnosticada con CloudWatch. Si el alumno anota la URL correcta (puerto 5003 de stock-service), el flujo funciona.

### 1.2 Anotar outputs del stack

Cuando el stack llegue a **CREATE_COMPLETE**:

1. Ir a pestana **Outputs**
2. Anotar:
   - `SiteNodeId` — ID de la EC2 (para Session Manager)
   - `FrontendTargetGroupArn` — ARN del TG del frontend
   - `MonolithTargetGroupArn` — ARN del TG del monolito
   - `PurchaseTargetGroupArn` — ARN del TG de purchase-service
   - `StockTargetGroupArn` — ARN del TG de stock-service
   - `PaymentTargetGroupArn` — ARN del TG de payment-service
   - `BrokenPurchaseStockServiceUrl` — confirma la URL rota

Tambien anotar el **DNS del ALB** desde los outputs del prereqs (o desde **EC2 > Load Balancers** si se uso uno existente).

> **¿Por que hay 5 target groups si solo usamos 2 al inicio?** Cada servicio futuro tiene su target group desde el momento cero, aunque nadie le envie trafico todavia. Esto permite que los health checks ya esten activos y que el alumno pueda verificar que los servicios responden antes de conectar las reglas del ALB.

### Troubleshooting de la Fase 1

| Sintoma | Posible causa | Correccion |
|---|---|---|
| Stack queda en `CREATE_FAILED` | Parametro incorrecto (VPC, subnet, SG ID) | Revisar eventos del stack en CloudFormation > Events |
| Stack no arranca por timeout de UserData | EC2 sin salida a internet o AMI incorrecto | Verificar que la subnet publica tenga ruta `0.0.0.0/0 -> IGW` |
| Error `ALBListenerArn` invalido | El ARN no corresponde a un listener HTTP :80 | Verificar que sea el ARN del listener, no del ALB |

---

## Fase 2: Verificar el sitio y el flujo monolitico

Antes de dividir nada, hay que saber que el sitio funciona. Si la compra monolitica no anda, no tiene sentido crear reglas de microservicios.

### 2.1 Abrir el sitio

1. Abrir el navegador en `http://<DNS-del-ALB>/`
2. Deberian verse los seis televisores Sorny con sus miniaturas y precios

> **¿Que estamos viendo?** El frontend es una pagina HTML estatica servida por Flask. Cuando carga, pide la lista de productos a `/api/products`. Esa peticion va al ALB, que siguiendo la regla `/api/*` la envia al backend monolitico. El monolito responde con los seis modelos. Todo funciona con una sola aplicacion.

### 2.2 Probar la compra monolitica

1. En el sitio, hacer click en **Comprar ahora** en cualquier televisor
2. El sitio deberia mostrar "Compra iniciada" y un enlace **Ir al checkout**
3. Click en **Ir al checkout** — deberia abrir un formulario de pago

> **¿Que paso atras?** El frontend envio un POST a `/api/purchases` con el SKU del televisor. El monolito recibio la solicitud, encontro el producto, verifico que habia stock (3 unidades de cada modelo), descontó uno, genero un ID de compra y devolvio un enlace de pago. Todo en el mismo proceso, puerto 5001.

### 2.3 Ver los productos desde la API

Probar directamente los endpoints del monolito:

1. Abrir `http://<DNS-del-ALB>/api/products`
2. Deberia verse el JSON con los 6 modelos y `"backend": "monolithic-backend"`
3. Abrir `http://<DNS-del-ALB>/api/health`
4. Deberia responder `{"service": "monolithic-backend", "status": "ok"}`

> **¿Por que "monolithic-backend"?** La API responde con un campo `backend` que indica que aplicacion manejo la request. Cuando las reglas del ALB cambien, ese campo mostrara `purchase-service`, `stock-service` o `payment-service`. Es util para confirmar por que servicio paso la peticion.

---

## Fase 3: Inspeccionar los componentes en AWS

Antes de cambiar reglas, hay que ubicar los recursos. En produccion, no se toca configuracion sin antes saber que existe.

### 3.1 Ubicar los target groups

1. Ir a **EC2 > Target Groups**
2. Buscar los target groups que empiezan con `sorni-`
3. Identificar:
   - `sorni-Front-*` (frontend, puerto 5000)
   - `sorni-Monol-*` (monolith, puerto 5001)
   - `sorni-Purch-*` (purchase-service, puerto 5002)
   - `sorni-Stock-*` (stock-service, puerto 5003)
   - `sorni-Payme-*` (payment-service, puerto 5004)
4. Abrir cada uno y revisar la pestana **Targets**:
   - `frontend` y `monolithic-backend` deberian estar **healthy**
   - `purchase-service`, `stock-service`, `payment-service` pueden estar **unused** (sin reglas del ALB que les envien trafico)

> **¿Que significa "unused"?** Un target group sin reglas del ALB que lo referencien aparece como `unused`. No es un error: los servicios estan vivos en la EC2, sus health checks pasan, pero nadie les envia trafico desde el ALB. Cuando se creen las reglas path-based, pasaran a `healthy`.

### 3.2 Revisar las reglas actuales del ALB

1. Ir a **EC2 > Load Balancers**
2. Seleccionar el ALB del laboratorio (nombre `sorni-ms-*`)
3. Ir a pestana **Listeners**
4. Click en el listener HTTP `:80`
5. En la pestana **Rules** deberian verse:
   - **Priority 100:** `IF path is /api/* THEN forward to sorni-Monol-*`
   - **Priority 200:** `IF path is /* THEN forward to sorni-Front-*`
   - **Default rule:** fixed-response 404

> **¿Por que el orden de prioridades?** El ALB evalua las reglas de menor numero de prioridad a mayor. Una request a `/api/purchases` coincide con `/api/*` en priority 100, asi que va al monolito. Una request a `/` no coincide con `/api/*`, pasa a priority 200, coincide con `/*` y va al frontend. Si ninguna regla coincide, usa la default (404).

### 3.3 Verificar que los servicios separados responden

Los servicios `purchase`, `stock` y `payment` estan vivos en la EC2 pero sin trafico del ALB. Para verificarlos localmente, entrar a la instancia via Session Manager:

1. Ir a **EC2 > Instances**
2. Buscar la instancia del stack (usando el `SiteNodeId` anotado antes)
3. Seleccionarla > **Connect**
4. Ir a pestana **Session Manager** > **Connect**
5. En la terminal que se abre, probar:

```bash
curl -s http://127.0.0.1:5002/api/purchases/health
curl -s http://127.0.0.1:5003/api/stock/health
curl -s http://127.0.0.1:5004/api/payments/health
```

6. Los tres comandos deberian responder `{"service": "...", "status": "ok"}`

> **¿Por que entrar por Session Manager y no por SSH?** Session Manager no requiere puertos abiertos, claves SSH ni IP publica. La instancia solo necesita el IAM Role con `AmazonSSMManagedInstanceCore`. Es la forma recomendada por AWS para acceso administrativo a EC2.

---

## Fase 4: Crear reglas path-based del ALB hacia los servicios separados

El ALB decide a que target group enviar cada request segun la ruta. Hasta ahora, todo `/api/*` va al monolito. Vamos a crear reglas mas especificas que enrute cada responsabilidad a su servicio.

> **¿Que cambia con las reglas path-based?** Sin reglas especificas, una request a `/api/purchases` va al monolito. Con una regla `/api/purchases/*` de prioridad 10 (menor que 100), la misma request va a `purchase-service`. El ALB evalua primero la regla mas especifica y de menor prioridad.

### 4.1 Crear regla para compras

1. Ir a **EC2 > Load Balancers**
2. Seleccionar el ALB
3. Pestana **Listeners** > click en el listener HTTP `:80`
4. Click en **View/edit rules** (o la pestana **Rules**)
5. Click en **Add rule**
6. En **Add rule**, configurar:
   - **Name:** `purchases-to-purchase-service` (opcional)
   - **Priority:** `10`
   - **Conditions > Add condition:**
     - **Condition type:** Path
     - **Path:** `/api/purchases`
   - Click en **Add another path**:
     - **Path pattern:** `/api/purchases/*`
   - **Actions > Add action:**
     - **Action type:** Forward to target group
     - **Target group:** seleccionar `sorni-Purch-*` (el que termina en `purchase-service`)
7. Click en **Save** (o **Add**)

> **¿Por que dos patrones de path?** El ALB evalua coincidencia exacta de patrones. `/api/purchaches` coincide con POST a `/api/purchases`, pero un GET a `/api/purchases/pur-abc123` no coincide. Agregando `/api/purchases/*` se cubren ambas variantes: el endpoint raiz y cualquier subruta.

### 4.2 Crear regla para stock

Repetir el mismo proceso:

1. Click en **Add rule**
2. Configurar:
   - **Priority:** `20`
   - **Condition > Path:** `/api/stock`
   - **Additional path pattern:** `/api/stock/*`
   - **Action:** Forward to `sorni-Stock-*`
3. Guardar

### 4.3 Crear regla para pagos

1. Click en **Add rule**
2. Configurar:
   - **Priority:** `30`
   - **Condition > Path:** `/api/payments`
   - **Additional path pattern:** `/api/payments/*`
   - **Action:** Forward to `sorni-Payme-*`
3. Guardar

### 4.4 Verificar el orden final de reglas

Despues de agregar las tres reglas, la lista del listener HTTP `:80` deberia verse asi:

| Prioridad | Path | Target group |
|---|---|---|
| 10 | `/api/purchases`, `/api/purchases/*` | `sorni-Purch-*` |
| 20 | `/api/stock`, `/api/stock/*` | `sorni-Stock-*` |
| 30 | `/api/payments`, `/api/payments/*` | `sorni-Payme-*` |
| 100 | `/api/*` | `sorni-Monol-*` |
| 200 | `/*` | `sorni-Front-*` |
| default | (ninguna) | fixed-response 404 |

> **¿Por que las prioridades 10, 20, 30?** El ALB evalua de menor a mayor prioridad. Una request a `/api/purchases/sorni-luma-32` coincide primero con la regla 10 (path `/api/purchases/*`) antes que con la 100 (path `/api/*`). Si una regla de microservicio tiene prioridad mayor que 100, la regla `/api/*` del monolito ganaria y la separacion no funcionaria.

### 4.5 Verificar que los servicios pasan a healthy

1. Ir a **EC2 > Target Groups**
2. Abrir `sorni-Purch-*`, `sorni-Stock-*`, `sorni-Payme-*`
3. En pestana **Targets**, deberian aparecer como **healthy**

Si alguno sigue `unused`, esperar unos segundos y refrescar.

---

## Fase 5: Probar el flujo con microservicios

Una vez que los target groups estan healthy, probar la compra desde el sitio.

### 5.1 Comprar un televisor

1. Ir al sitio `http://<DNS-del-ALB>/`
2. Click en **Comprar ahora** en cualquier televisor
3. Observar el resultado

**Resultado esperado:** La compra falla. El sitio muestra un mensaje como "No pudimos completar la compra" o "stock_service_unavailable".

> **¿Por que falla si los target groups estan healthy?** Esta es la pregunta clave del laboratorio. Los servicios estan vivos y respondiendo health checks, pero el flujo completo no funciona porque `purchase-service` intenta consultar stock en el puerto incorrecto (5999). Un servicio puede estar "vivo" y su target group "healthy", pero el flujo de negocio puede estar roto por una dependencia mal configurada.

### 5.2 Probar los endpoints directamente

Para confirmar que el enrutamiento del ALB funciona pero el flujo interno falla:

1. Probar stock directamente:
   - `http://<DNS-del-ALB>/api/stock/sorni-luma-32`
   - Deberia responder con stock disponible y `"backend": "stock-service"`
2. Probar payment directamente:
   - `http://<DNS-del-ALB>/api/payments/health`
   - Deberia responder `"backend": "payment-service"`
3. Probar purchase directamente (falla esperada):
   - Enviar POST a `http://<DNS-del-ALB>/api/purchases`
   - Deberia fallar con error `"stock_service_unavailable"`

> **¿Que nos dice esto?** stock-service y payment-service responden bien. El problema esta en purchase-service cuando intenta hablar con stock-service. El ALB enruta bien, pero la comunicacion interna entre servicios esta rota.

---

## Fase 6: Diagnosticar con CloudWatch

Cuando el flujo falla y no es obvio por que, la primer respuesta no es "reiniciar todo". Es mirar logs y metricas.

### 6.1 Revisar logs de purchase-service

1. Ir a **CloudWatch > Log groups**
2. Buscar el log group: `/sorny/microservices-site/site`
3. Abrirlo
4. Buscar el log stream `purchase-service`
5. Leer los mensajes mas recientes
6. Buscar el error al intentar reservar stock

El log deberia mostrar algo como:

```
stock reservation failed sku=sorni-luma-32 stock_service_url=http://127.0.0.1:5999/api/stock
Connection refused
```

> **¿Que muestra este log?** `purchase-service` intento consultar stock en `127.0.0.1:5999` y recibio "Connection refused". Ese puerto no existe en la EC2. El servicio de stock real corre en puerto 5003. El error esta en la URL configurada, no en stock-service.

### 6.2 Confirmar que stock-service no recibio la llamada

1. En el mismo log group, abrir el log stream `stock-service`
2. No deberian verse registros de reserva de stock para esa compra

Si `stock-service` nunca recibio la request, es porque `purchase-service` nunca llego a el.

### 6.3 Revisar metricas del ALB

1. Ir a **EC2 > Target Groups**
2. Seleccionar `sorni-Purch-*` (purchase-service)
3. Ir a pestana **Monitoring**
4. Revisar `HTTPCode_Target_5XX_Count`
5. Deberia haber picos de 503 (Service Unavailable) en los momentos en que se intento comprar

> **¿Por que 503 y no 500?** `purchase-service` devuelve 503 cuando no puede contactar a stock-service. Es intencional: 503 indica "el servicio esta funcionando pero no puede completar la request porque un recurso del que depende no responde". Es distinto de un 500 (error interno del servicio).

---

## Fase 7: Corregir la configuracion y validar

El diagnostico muestra la causa: `STOCK_SERVICE_URL` apunta al puerto 5999, cuando stock-service corre en puerto 5003.

### 7.1 Entrar a la EC2 por Session Manager

1. Ir a **EC2 > Instances**
2. Seleccionar la instancia del stack
3. **Connect > Session Manager > Connect**

### 7.2 Inspeccionar la configuracion actual

```bash
sudo systemctl cat sorni-purchase
```

Esto muestra el archivo de servicio systemd. La variable `Environment` deberia mostrar:

```
Environment=STOCK_SERVICE_URL=http://127.0.0.1:5999/api/stock
```

### 7.3 Corregir la URL del servicio

```bash
sudo systemctl edit sorni-purchase
```

Esto abre un editor en la terminal. Agregar:

```
[Service]
Environment=STOCK_SERVICE_URL=http://127.0.0.1:5003/api/stock
```

> **¿Por que usar `systemctl edit` y no modificar el archivo directamente?** `systemctl edit` crea un fragmento de configuracion que sobrescribe la variable del servicio sin tocar el archivo original. Si se actualiza el stack de CloudFormation, el archivo original se reescribe pero el fragmento sobrevive. Ademas, es la forma correcta de hacer overrides en systemd.

Guardar y salir del editor.

### 7.4 Recargar y reiniciar

```bash
sudo systemctl daemon-reload
sudo systemctl restart sorni-purchase
sudo systemctl status sorni-purchase --no-pager
```

Verificar que el servicio quedo `active (running)`.

### 7.5 Validar la variable corregida

```bash
sudo systemctl show sorni-purchase -p Environment
```

Deberia mostrar:

```
Environment=STOCK_SERVICE_URL=http://127.0.0.1:5003/api/stock PAYMENT_SERVICE_URL=http://127.0.0.1:5004/api/payments
```

### 7.6 Probar la compra nuevamente

1. Volver al sitio `http://<DNS-del-ALB>/`
2. Comprar un televisor
3. El flujo deberia completarse: mostrar "Compra iniciada" con un enlace a **Ir al checkout**

> **¿Por que ahora funciona?** `purchase-service` ahora consulta stock en el puerto correcto (5003). `stock-service` responde con el producto y descuenta inventario. `purchase-service` luego pide un enlace de pago a `payment-service`. `payment-service` lo genera. La compra se completa.

### 7.7 Confirmar que el backend cambio

Hacer una compra y revisar la respuesta:

```
http://<DNS-del-ALB>/api/purchases
```

La respuesta JSON ahora muestra `"backend": "purchase-service"`, no `"monolithic-backend"`. La request paso por purchase-service, no por el monolito.

---

## Limpieza

> **Atencion:** Si se continua con la siguiente clase, mantener el ALB, los target groups y el SG. Solo eliminar el stack del sitio.

### Eliminar stack del sitio

1. Ir a **CloudFormation > Stacks**
2. Seleccionar `sorny-microservices-site-bootstrap`
3. Click **Delete** > confirmar
4. Esperar a que el stack desaparezca (~3-5 minutos)

### Eliminar stack de prerequisitos (opcional)

Si se creo el stack auxiliar y ya no se necesita:

1. Ir a **CloudFormation > Stacks**
2. Seleccionar `sorny-microservices-prereqs`
3. Click **Delete** > confirmar
4. Esperar (~2 minutos)

### NO eliminar (recursos persistentes del curso)

- VPC, subnets, Internet Gateway, route tables
- IAM Role SSM + Instance Profile (reutilizables en otros laboratorios)

---

## Criterios de exito

- El sitio Sorny responde con los 6 televisores en `http://<DNS-del-ALB>/`
- La compra monolitica funciona (Fase 2)
- Los target groups de frontend y monolith estan healthy
- Los target groups de purchase, stock y payment pasan a healthy al crear reglas del ALB
- Sin las reglas path-based, la compra falla con error `stock_service_unavailable`
- Los logs de CloudWatch muestran el error de conexion a puerto 5999
- Corrigiendo `STOCK_SERVICE_URL` al puerto 5003, la compra funciona
- La respuesta de la API muestra `"backend": "purchase-service"` despues de la correccion
- Se puede explicar por que un servicio puede estar "healthy" pero el flujo completo falla

---

## Proximo paso

Una vez completado este laboratorio, aparece una pregunta para el siguiente modulo: "si cada servicio estuviera en su propia EC2 con su propio ALB, que cambiaria en la forma de diagnosticar fallas?".

Tambien quedan temas pendientes para produccion real:

- HTTPS
- Base de datos persistente (hoy el estado vive en memoria)
- Transacciones entre servicios (consistencia compra/stock/pago)
- Timeouts, retries y circuit breakers
- Despliegue automatizado
- Trazabilidad con correlation IDs