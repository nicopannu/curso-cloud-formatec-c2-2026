# Guia Microservicios 02: Sorny, de monolito a servicios pequenos en AWS

## Objetivo

Vas a partir de una aplicacion web funcional y vas a separar parte de su backend monolitico en servicios mas pequenos.

El caso se llama **Sorny**, una tienda de televisores. El negocio es simple para que el foco este en arquitectura: rutas, contratos, dependencias y observabilidad.

Nota de nombres: la marca visible es **Sorny**. Algunos identificadores tecnicos pueden mantener `sorni-*` por compatibilidad con recursos ya creados; no cambia el flujo de la practica.

## Desafio

Sorny tiene una pagina web que vende seis modelos de televisores. El flujo inicial funciona asi:

```text
cliente selecciona televisor
  |
  v
frontend envia solicitud de compra
  |
  v
backend monolitico revisa stock
  |
  v
backend monolitico genera enlace de pago
  |
  v
frontend muestra pantalla de pago
```

Tu desafio es dividir el backend en tres responsabilidades:

- compras;
- stock;
- pagos.

La consigna central es:

> Mantengan el sitio Sorny funcionando, separen compras, stock y pagos en servicios independientes, reconecten el flujo desde el frontend, y usen CloudWatch para diagnosticar por que el primer intento con microservicios falla.

## Por que hacemos esto

Microservicios no significa "crear muchas aplicaciones". Significa separar responsabilidades con contratos claros.

En un monolito, una compra puede revisar stock y generar el pago con llamadas internas dentro del mismo proceso. Cuando dividimos esa logica, aparecen preguntas nuevas:

- que servicio recibe la compra;
- que servicio es dueno del inventario;
- que servicio genera el enlace de pago;
- como se comunican entre si;
- que pasa si uno responde lento o falla;
- donde miro logs si el flujo completo no funciona.

La idea es ver esa complejidad con tus propias manos.

## Duracion estimada

2 a 3 horas.

## Arquitectura inicial

```text
Usuario
  |
  v
ALB
  |
  +-- /      -> frontend
  |
  +-- /api/* -> backend monolitico
                  |
                  +-- GET  /api/products
                  +-- POST /api/purchases
                  +-- GET  /api/purchases/<id>
                  +-- POST /api/payments/checkout
```

El backend monolitico tiene todo junto: catalogo, compras, stock y pago.

Esto es facil de arrancar, pero tiene un costo: si falla el flujo de compra, cuesta distinguir si el problema esta en stock, pagos, logica de compra, datos o infraestructura.

## Arquitectura final esperada

```text
Usuario
  |
  v
ALB
  |
  +-- /                   -> frontend
  |
  +-- /api/*              -> backend monolitico (fallback inicial)
  |
  +-- /api/purchases/*    -> purchase-service
  |
  +-- /api/stock/*        -> stock-service
  |
  +-- /api/payments/*     -> payment-service

purchase-service
  |
  +-- consulta stock-service
  |
  +-- solicita enlace a payment-service
```

Servicios:

| Servicio | Responsabilidad | Por que se separa |
|---|---|---|
| `frontend` | Mostrar televisores, enviar compra y mostrar checkout | Es la experiencia del cliente |
| `monolithic-backend` | Resolver todo el flujo inicial | Punto de partida conocido |
| `purchase-service` | Recibir compra y coordinar stock + pago | La compra es el caso de uso principal |
| `stock-service` | Validar y reservar inventario | Stock cambia por reglas propias y debe ser observable |
| `payment-service` | Generar enlace de pago | Pagos suelen tener integracion, seguridad y auditoria propias |

## Modelos Sorny

El frontend muestra estos seis televisores:

| SKU | Modelo | Descripcion | Precio |
|---|---|---|---:|
| `sorni-luma-32` | Sorny Luma 32 | LED 32 pulgadas para habitacion o cocina | 189999 |
| `sorni-braviax-43` | Sorny Braviax 43 | Smart TV 43 pulgadas Full HD | 319999 |
| `sorni-croma-50` | Sorny Croma 50 | 4K 50 pulgadas con HDR basico | 489999 |
| `sorni-trinitronix-55` | Sorny Trinitronix 55 | 4K 55 pulgadas, panel rapido para deportes | 629999 |
| `sorni-cinepro-65` | Sorny CinePro 65 | 4K 65 pulgadas para living grande | 899999 |
| `sorni-mega-75` | Sorny Mega 75 | 75 pulgadas, experiencia cine en casa | 1299999 |

Los nombres no son lo importante: el flujo tecnico es el punto.

## Componentes AWS

Componentes:

- Application Load Balancer.
- Target groups por servicio.
- EC2 para ejecutar los procesos.
- Security Groups.
- CloudWatch Logs.
- CloudWatch Metrics del ALB y de EC2.
- CloudWatch Alarms para detectar comportamiento anomalo.

La version de bootstrap usa una sola EC2 con varios procesos en puertos distintos. Antes de sumar Docker, ECS, EKS o Lambda, necesitamos entender rutas, contratos, health checks, logs y dependencias.

## Que levanta el bootstrap y que hace el alumno

### Bootstrap

Levanta:

- una EC2;
- cinco aplicaciones pequenas como procesos separados;
- target groups separados;
- CloudWatch Logs;
- alarma base de EC2;
- reglas base del ALB si `CreateBaseAlbRules=true`.

Para clase conviene usar:

```text
CreateBaseAlbRules=true
CreateMicroserviceAlbRules=false
```

Asi el sitio queda funcionando contra el monolito y el alumno crea las reglas de microservicios.

### Alumno

El alumno debe:

- probar que el flujo monolitico funciona;
- identificar que responsabilidades se van a separar;
- crear o revisar reglas path-based del ALB;
- probar endpoints separados;
- reconectar el flujo hacia `purchase-service`;
- observar que falla;
- usar CloudWatch para encontrar el motivo;
- corregir la configuracion;
- explicar que aprendio de la falla.

## Stack 1 - Sitio funcional y APIs separadas

El primer objetivo es levantar la aplicacion y comprobar que existen dos mundos:

1. el sitio funcional con backend monolitico;
2. las APIs separadas listas para ser conectadas.

No reconectamos todo de golpe porque eso oculta el aprendizaje. Primero validamos que cada pieza vive, responde y tiene health check.

### Endpoints base

```text
GET  /
GET  /health
GET  /api/health
GET  /api/products
POST /api/purchases
```

### Endpoints de servicios separados

```text
GET  /api/purchases/health
POST /api/purchases

GET  /api/stock/health
GET  /api/stock/<sku>
POST /api/stock/reserve

GET  /api/payments/health
POST /api/payments/checkout
```

### Por que importa esta etapa

Antes de mover trafico, hay que saber si los servicios existen y si el ALB puede llegar a ellos. En produccion, separar sin health checks ni pruebas basicas es cambiar demasiadas variables al mismo tiempo.

### Verificacion inicial en AWS Console

Usa la interfaz de AWS para ubicar los recursos antes de cambiar nada:

1. Ir a **CloudFormation**.
2. Abrir el stack principal.
3. Entrar a la solapa **Outputs**.
4. Anotar:
   - `FrontendTargetGroupArn`;
   - `MonolithTargetGroupArn`;
   - `PurchaseTargetGroupArn`;
   - `StockTargetGroupArn`;
   - `PaymentTargetGroupArn`;
   - `SiteNodeId`.
5. Ir a **EC2 > Target Groups**.
6. Buscar los target groups del stack.
7. Confirmar:
   - `frontend` y `monolithic-backend` aparecen `healthy`;
   - `purchase-service`, `stock-service` y `payment-service` pueden aparecer `unused` mientras no existan reglas del listener que los usen.

Los target groups ya existen. En esta practica no hace falta crearlos desde cero; el trabajo principal es revisar health checks y conectar reglas del ALB.

Luego:

1. Ir a **EC2 > Load Balancers**.
2. Abrir el ALB de la practica.
3. Entrar a **Listeners and rules**.
4. Abrir el listener HTTP `:80`.
5. Confirmar que existan las reglas base:
   - `/api/*` hacia el target group del monolito;
   - `/*` hacia el target group del frontend.

Con esas reglas base, el sitio funciona contra el backend monolitico.

## Practica 1 - Probar flujo y reconectar con microservicios

Objetivo:

Pasar el flujo de compra desde el monolito hacia servicios separados.

Arquitectura durante la practica:

```text
ALB
  |
  +-- /                 -> frontend
  +-- /api/*            -> monolith fallback
  +-- /api/purchases/*  -> purchase-service
  +-- /api/stock/*      -> stock-service
  +-- /api/payments/*   -> payment-service
```

Tareas:

1. Abrir el sitio desde el DNS del ALB.
2. Comprar un televisor usando el flujo monolitico.
3. Confirmar que aparece un enlace de pago.
4. Volver a **EC2 > Target Groups**.
5. Revisar estos target groups existentes:
   - `purchase-service`, puerto `5002`, health check `/api/purchases/health`;
   - `stock-service`, puerto `5003`, health check `/api/stock/health`;
   - `payment-service`, puerto `5004`, health check `/api/payments/health`.
6. Si aparecen `unused`, no es un error todavia: significa que aun no hay reglas del listener enviandoles trafico.
7. Ir a **EC2 > Load Balancers**.
8. Abrir el ALB.
9. Entrar al listener HTTP `:80`.
10. Elegir **Manage rules**.
11. Elegir **Add rule**.
12. Crear estas reglas nuevas con numero de prioridad menor que `/api/*`, que normalmente queda en `100`:

```text
Priority 10
IF path is /api/purchases OR /api/purchases/*
THEN forward to purchase-service target group
```

```text
Priority 20
IF path is /api/stock OR /api/stock/*
THEN forward to stock-service target group
```

```text
Priority 30
IF path is /api/payments OR /api/payments/*
THEN forward to payment-service target group
```

13. En cada regla, usar:
   - condicion **Path**;
   - accion **Forward to target group**;
   - el target group correspondiente.
14. Guardar los cambios.
15. Revisar que la regla `/api/*` quede con prioridad mayor, por ejemplo `100`.
16. Volver a **EC2 > Target Groups** y confirmar que los tres servicios pasen de `unused` a `healthy`.
17. Probar nuevamente la compra desde el frontend.

Resultado esperado:

El flujo falla. No se sabe bien por que al mirar solo la pantalla del navegador.

Cuando una aplicacion se divide, el error del usuario final suele ser generico, pero la causa real queda distribuida entre servicios.

## Practica 2 - Diagnosticar en CloudWatch y corregir

Objetivo:

Usar CloudWatch para encontrar por que falla la compra con microservicios.

### Hipotesis de falla preparada

`purchase-service` intenta consultar stock usando una URL mal configurada:

```text
STOCK_SERVICE_URL=http://127.0.0.1:5999/api/stock
```

El valor correcto en esta version es:

```text
STOCK_SERVICE_URL=http://127.0.0.1:5003/api/stock
```

No queremos que el alumno "adivine el puerto". Queremos que vea el error en logs, entienda que `purchase-service` depende de `stock-service` y corrija la configuracion.

### Pasos de diagnostico

1. Ir a CloudWatch Logs.
2. Abrir el log group del stack:

```text
/<ProjectName>/<Environment>/site
```

3. Revisar primero el stream `purchase-service`.
4. Buscar errores al intentar reservar stock.
5. Abrir el stream `stock-service`.
6. Confirmar si `stock-service` recibio o no recibio la llamada.
7. Ir a **EC2 > Target Groups**.
8. Abrir el target group de `purchase-service`.
9. Revisar **Monitoring** y buscar `HTTPCode_Target_5XX_Count`.
10. Ir al ALB y revisar metricas del listener si hace falta.

El dato clave es este: el target group puede estar `healthy`, pero el flujo puede fallar porque `purchase-service` llama mal a `stock-service`.

### Correccion desde AWS Console y Session Manager

La correccion de la practica se hace desde la consola de AWS, entrando a la EC2 con Session Manager:

1. Ir a **EC2 > Instances**.
2. Buscar la instancia del stack usando el output `SiteNodeId`.
3. Seleccionarla.
4. Elegir **Connect**.
5. Abrir la solapa **Session Manager**.
6. Elegir **Connect**.
7. Revisar la configuracion actual del servicio:

```bash
sudo systemctl cat sorni-purchase
```

8. Editar el servicio:

```bash
sudo systemctl edit sorni-purchase
```

9. Agregar este contenido en el editor:

```ini
[Service]
Environment=STOCK_SERVICE_URL=http://127.0.0.1:5003/api/stock
```

10. Guardar y salir del editor.
11. Recargar systemd y reiniciar el servicio:

```bash
sudo systemctl daemon-reload
sudo systemctl restart sorni-purchase
sudo systemctl status sorni-purchase --no-pager
```

12. Validar que la variable quedo corregida:

```bash
sudo systemctl show sorni-purchase -p Environment
```

13. Volver al sitio y repetir la compra.

Para una correccion permanente del stack, el docente puede actualizar el parametro `PurchaseStockServiceUrl` en CloudFormation antes de relanzar el entorno.

### Comandos utiles en la EC2

Usar estos comandos solo dentro de Session Manager. No usar PowerShell ni scripts locales.

```bash
sudo systemctl status sorni-purchase
sudo journalctl -u sorni-purchase -n 80 --no-pager
sudo systemctl cat sorni-purchase
```

Si el stack ya fue actualizado y el servicio necesita reinicio:

```bash
sudo systemctl daemon-reload
sudo systemctl restart sorni-purchase
```

### Preguntas guia

- El target group esta healthy, pero el flujo falla. Que significa eso?
- El error esta en frontend, ALB, purchase, stock o payments?
- `stock-service` recibio la request?
- Que log muestra primero la causa real?
- Que alarma podria detectar este problema antes de que avise un usuario?
- Que cambiaria si cada servicio estuviera en una EC2 distinta?

## Variantes para ajustar la practica

Variantes posibles para pensar juntos:

1. **Falla por URL incorrecta:** la version recomendada para la primera practica. Es clara, comun y se ve bien en CloudWatch.
2. **Falla por prioridad de regla ALB:** `/api/*` queda con prioridad mas alta que `/api/purchases/*`, entonces la compra sigue yendo al monolito. Sirve para ensenar path routing.
3. **Falla por contrato:** `purchase-service` envia `product_id`, pero `stock-service` espera `sku`. Sirve para hablar de contratos entre equipos.
4. **Falla por timeout:** `stock-service` duerme 4 segundos y `purchase-service` tiene timeout de 2. Sirve para discutir latencia, retries y circuit breakers.
5. **Falla por stock insuficiente:** no es infraestructura, es regla de negocio. Sirve para que no diagnostiquen todo como si fuera AWS.
6. **Falla por payment service sano pero respuesta distinta:** `payment-service` responde `checkout_url`, pero `purchase-service` espera `payment_url`. Sirve para versionado de APIs.

Mi recomendacion para esta clase:

- Practica 1: falla por URL incorrecta hacia stock.
- Practica 2: diagnostico con CloudWatch Logs + ALB `5XX`.
- Discusion final: mostrar las otras fallas como "lo que pasaria en un equipo real".

Asi la falla es simple, pero obliga a usar observabilidad.

## Discusion tecnica: por que separar compras, stock y pagos

### Compras

`purchase-service` representa el caso de uso principal. Recibe una intencion del cliente y coordina pasos.

Separarlo ayuda a que el equipo pueda evolucionar reglas de compra sin tocar todo el backend. Pero tambien lo convierte en un orquestador: si stock o pagos fallan, compra debe responder de forma controlada.

### Stock

`stock-service` es dueno del inventario. Esta separacion tiene sentido porque el stock cambia por compras, reposiciones, cancelaciones y devoluciones.

Si stock estuviera mezclado con pagos, seria mas dificil auditar por que una unidad desaparecio del inventario.

### Pagos

`payment-service` genera un enlace de pago. En un sistema real, este servicio podria integrarse con un proveedor externo y manejar reglas de seguridad, auditoria y estados de pago.

Separarlo evita que el resto del backend conozca detalles del proveedor de pago.

## Entregables

Cada grupo entrega:

1. Diagrama inicial del monolito.
2. Diagrama final con servicios separados.
3. Captura o salida del flujo monolitico funcionando.
4. Evidencia de regla ALB para `/api/purchases/*`.
5. Evidencia de regla ALB para `/api/stock/*`.
6. Evidencia de regla ALB para `/api/payments/*`.
7. Captura o salida del error inicial al reconectar microservicios.
8. Evidencia de logs en CloudWatch que muestran la causa.
9. Correccion aplicada.
10. Captura o salida del flujo funcionando luego de corregir.

## Rubrica

Total: 100 puntos.

| Criterio | Puntos |
|---|---:|
| Prueba correctamente el flujo monolitico inicial | 15 |
| Configura rutas y target groups de microservicios | 25 |
| Diagnostica la falla usando CloudWatch | 25 |
| Corrige la configuracion y valida el flujo | 20 |
| Explica el por que de la separacion y sus trade-offs | 15 |

## Que faltaria para produccion

- HTTPS.
- Base de datos real y persistente.
- Transacciones o manejo de consistencia entre compra, stock y pago.
- Idempotencia para evitar compras duplicadas.
- Integracion real con proveedor de pago.
- Secrets fuera del codigo.
- IAM y security groups con minimo privilegio.
- Logs sin datos sensibles de tarjeta.
- Trazabilidad con correlation ID.
- Timeouts, retries y circuit breakers.
- Dashboards y alarmas accionables.
- Deploy automatizado.
- Tests de contrato entre servicios.

## Cierre docente

Frase:

> Separar servicios no elimina la complejidad. La mueve hacia contratos, comunicacion y observabilidad.

Pregunta final:

> Si todos los health checks dan OK pero la compra falla, que aprendimos sobre la diferencia entre "servicio vivo" y "flujo sano"?
