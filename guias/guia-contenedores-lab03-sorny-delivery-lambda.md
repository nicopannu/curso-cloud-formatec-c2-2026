# Guia Contenedores LAB03: Sorny — llevar delivery-service a AWS Lambda

**Objetivo:** continuar desde la arquitectura con ALB, frontend en EC2 y dos servicios en Docker Swarm. En esta parte, `delivery-service` no se despliega como contenedor: se implementa como funcion Lambda, con codigo ZIP almacenado en S3 y exposicion HTTP desde API Gateway.

**Duracion estimada:** 1.5 a 2 horas

**Modulo:** Modulo 2 — Clase 4: Contenedores y Serverless

---

## Contexto narrativo

En el LAB02, Sorny migro dos APIs a un modelo de servicios contenedorizados:

```text
purchase-service -> Docker Swarm en 2 EC2
payment-service  -> Docker Swarm en 2 EC2
```

Ahora aparece una decision distinta. `delivery-service` recibe una solicitud corta para coordinar envio/contacto:

```text
POST /api/delivery
```

No necesita mantener un proceso corriendo todo el tiempo, no administra sesiones y puede ejecutarse como reaccion a un evento HTTP. Por eso, en este lab se modela como Lambda.

La pregunta de arquitectura es:

```text
Cuando conviene operar un servicio contenedorizado y cuando conviene ejecutar una funcion por evento?
```

---

## Arquitectura de partida

La arquitectura que viene del LAB02 queda asi:

```text
Usuario
  |
  v
ALB publico
  |
  +-- /*                               -> frontend EC2 publica
  +-- /api/purchases/*                 -> Docker Swarm puerto 5003
  +-- /api/payments/*                  -> Docker Swarm puerto 5004

Docker Swarm:
  - swarm-manager EC2 publica
  - swarm-worker EC2 publica
```

En esta guia agregamos `delivery-service` como Lambda.

---

## Arquitectura objetivo del lab

Implementacion principal, paso a paso por consola:

```text
Cliente de prueba / navegador / curl
  |
  v
API Gateway HTTP API
  |
  v
Lambda sorny-delivery-handler
  |
  v
CloudWatch Logs
```

El ALB y el frontend siguen existiendo para purchases/payments. API Gateway se usa para que la parte Lambda sea clara y realizable en una clase.

Extension opcional para discusion:

```text
ALB /api/delivery -> Target Group tipo Lambda -> Lambda
```

Esa opcion mantiene frente unico por ALB, pero agrega permisos e integracion adicional. Para el lab obligatorio usamos API Gateway.

---

## Objetivos de aprendizaje

Al finalizar, deberias poder:

- explicar por que `delivery-service` puede modelarse como funcion;
- crear una Lambda desde AWS Console;
- subir codigo ZIP a S3 y usarlo como artefacto de despliegue;
- configurar runtime, handler, timeout y memoria;
- probar una Lambda con eventos JSON;
- exponer una Lambda con API Gateway HTTP API;
- revisar logs en CloudWatch;
- comparar Docker Swarm y Lambda como modelos de ejecucion.

---

## Alcance del lab

### Obligatorio

- Crear bucket S3 para artefactos del lab.
- Subir el ZIP de `delivery-service`.
- Crear Lambda desde consola usando ese ZIP.
- Probar evento valido e invalido.
- Crear API Gateway HTTP API con ruta `POST /api/delivery`.
- Validar respuesta HTTP.
- Revisar CloudWatch Logs.

### Opcional

- Conectar Lambda al ALB como target Lambda.
- Agregar variable `STAGE`.
- Agregar permisos mas finos de IAM.
- Agregar una regla desde el frontend para mostrar la URL de API Gateway.

---

## Artefactos del repo

El repo trae codigo listo:

```text
lambda/sorny-delivery-lambda/app.py
lambda/sorny-delivery-lambda/sorny-delivery-lambda.zip
```

Handler:

```text
app.lambda_handler
```

El ZIP debe contener `app.py` en la raiz.

---

## Fase 1: Revisar contrato de delivery-service

Endpoint objetivo:

```text
POST /api/delivery
```

Payload sugerido:

```json
{
  "purchase_id": "pur-abc12345",
  "name": "Ana Perez",
  "email": "ana@example.com",
  "product_name": "Sorny Luma 32"
}
```

Respuesta esperada:

```json
{
  "status": "delivery_pending",
  "message": "Te contactaremos para coordinar el envio",
  "backend": "delivery-lambda"
}
```

Decision importante:

```text
El contrato HTTP se mantiene, pero cambia el runtime: ya no hay EC2 ni contenedor dedicado para delivery.
```

---

## Fase 2: Crear bucket S3 para artefactos

Desde AWS Console:

```text
S3 > Create bucket
```

Nombre sugerido:

```text
sorny-delivery-lambda-<iniciales>-<numero>
```

Region: misma region del lab.

Configuracion:

- bloquear acceso publico: habilitado;
- versioning: opcional;
- encryption: default SSE-S3.

Crear bucket.

Subir objeto:

```text
lambda/sorny-delivery-lambda/sorny-delivery-lambda.zip
```

Anotar:

- bucket name;
- object key: `sorny-delivery-lambda.zip` o la ruta usada.

Checkpoint:

```text
S3 no ejecuta codigo. S3 almacena el artefacto que Lambda va a cargar.
```

---

## Fase 3: Crear Lambda desde consola

Ir a:

```text
Lambda > Functions > Create function
```

Seleccionar:

```text
Author from scratch
```

Valores:

| Campo | Valor |
|---|---|
| Function name | `sorny-delivery-handler` |
| Runtime | Python 3.12 |
| Architecture | x86_64 |
| Execution role | crear nuevo role basico |

Crear funcion.

Configurar codigo desde S3:

```text
Code > Upload from > Amazon S3 location
```

Ingresar URL S3 del objeto ZIP o seleccionar bucket/key segun la consola.

Configurar handler:

```text
Runtime settings > Edit
Handler: app.lambda_handler
```

Configurar runtime:

| Setting | Valor sugerido |
|---|---|
| Memory | 128 MB |
| Timeout | 5 seconds |
| Ephemeral storage | default |

Agregar variable opcional:

```text
STAGE=lab
```

---

## Fase 4: Probar Lambda con evento valido

Crear test event:

```text
Test > Create new event
Event name: delivery-valid
```

Evento:

```json
{
  "body": "{\"purchase_id\":\"pur-123\",\"name\":\"Ana\",\"email\":\"ana@example.com\",\"product_name\":\"Sorny Luma 32\"}",
  "headers": {
    "content-type": "application/json"
  },
  "requestContext": {
    "http": {
      "method": "POST",
      "path": "/api/delivery"
    }
  }
}
```

Ejecutar test.

Resultado esperado:

```json
{
  "statusCode": 200,
  "headers": {
    "Content-Type": "application/json"
  },
  "body": "{...}"
}
```

Abrir el body y verificar:

- `status = delivery_pending`;
- `backend = delivery-lambda`;
- `runtime = lambda`.

---

## Fase 5: Probar validacion de errores

Crear evento invalido:

```json
{
  "body": "{\"name\":\"Ana\"}",
  "requestContext": {
    "http": {
      "method": "POST",
      "path": "/api/delivery"
    }
  }
}
```

Resultado esperado:

```text
statusCode: 400
```

La funcion debe indicar campos faltantes.

Checkpoint:

```text
Serverless no elimina la responsabilidad de validar entradas. Solo cambia donde y cuando corre el codigo.
```

---

## Fase 6: Revisar logs en CloudWatch

Desde Lambda:

```text
Monitor > View CloudWatch logs
```

Buscar el log group:

```text
/aws/lambda/sorny-delivery-handler
```

Identificar:

- inicio de invocacion;
- request id;
- payload procesado;
- errores si los hubo;
- duracion y memoria usada.

Preguntas:

- Donde se ve una excepcion de codigo?
- Que diferencia hay entre un error 400 controlado y un error 502/500 por excepcion?
- Que dato usarias para correlacionar una compra con un pedido de envio?

---

## Fase 7: Crear API Gateway HTTP API

Ir a:

```text
API Gateway > Create API > HTTP API > Build
```

Integracion:

```text
Integration type: Lambda
Lambda function: sorny-delivery-handler
```

Configurar ruta:

```text
Method: POST
Resource path: /api/delivery
```

Stage:

```text
$default
Auto-deploy: enabled
```

Crear API.

Anotar Invoke URL:

```text
https://<api-id>.execute-api.<region>.amazonaws.com
```

---

## Fase 8: Probar API publica

Desde CloudShell, terminal local o navegador compatible con POST:

```bash
curl -X POST https://<api-id>.execute-api.<region>.amazonaws.com/api/delivery \
  -H 'Content-Type: application/json' \
  -d '{"purchase_id":"pur-123","name":"Ana","email":"ana@example.com","product_name":"Sorny Luma 32"}'
```

Resultado esperado:

```json
{
  "status": "delivery_pending",
  "message": "Te contactaremos para coordinar el envio",
  "backend": "delivery-lambda",
  "runtime": "lambda"
}
```

Comparar con servicios Swarm:

```bash
curl http://<AlbDnsName>/api/purchases/health
curl http://<AlbDnsName>/api/payments/health
```

Conclusiones esperadas:

- purchases/payments viven detras del ALB y corren en Swarm;
- delivery vive detras de API Gateway y corre por invocacion Lambda;
- son modelos de ejecucion distintos, no solo formas distintas de hacer deploy.

---

## Fase 9 opcional: Integrar Lambda detras del ALB

Solo si hay tiempo.

Idea:

```text
ALB listener rule /api/delivery -> Target Group tipo Lambda -> Lambda
```

Pasos conceptuales:

1. Crear Target Group de tipo `Lambda`.
2. Registrar `sorny-delivery-handler` como target.
3. Permitir invocacion desde Elastic Load Balancing.
4. Crear regla en el listener del ALB para `/api/delivery`.
5. Probar:

```bash
curl -X POST http://<AlbDnsName>/api/delivery -H 'Content-Type: application/json' -d '{...}'
```

Trade-off:

- mas coherencia de entrada unica;
- mas configuracion IAM/ALB;
- menos foco si el objetivo principal es aprender Lambda.

---

## Comparacion: Swarm vs Lambda

| Dimension | Docker Swarm en EC2 | Lambda |
|---|---|---|
| Unidad de ejecucion | Servicio con replicas | Invocacion de funcion |
| Capacidad idle | EC2 encendidas aunque no haya trafico | Sin ejecucion si no hay eventos |
| Escalado | replicas/nodos administrados por equipo | concurrencia administrada por AWS |
| Operacion de host | responsabilidad del equipo | abstraida |
| Entrada HTTP | ALB hacia puertos publicados | API Gateway o ALB Lambda target |
| Mejor para | APIs persistentes, servicios internos, control de runtime | acciones cortas, stateless, orientadas a eventos |
| Riesgo principal | operar cluster y parches | limites, cold start, permisos, observabilidad distribuida |

Decision para Sorny:

```text
purchase-service y payment-service necesitan comportarse como servicios replicados.
delivery-service puede ejecutarse como accion corta por evento HTTP.
```

---

## Limpieza

Si se uso solo Lambda/API Gateway/S3:

1. API Gateway:

```text
API Gateway > APIs > seleccionar API > Delete
```

2. Lambda:

```text
Lambda > Functions > sorny-delivery-handler > Delete
```

3. S3:

```text
Vaciar bucket > Delete bucket
```

4. CloudWatch Logs:

```text
CloudWatch > Log groups > /aws/lambda/sorny-delivery-handler > Delete
```

Si tambien se hizo extension ALB, eliminar primero la regla y el target group Lambda.

---

## Entregables

Cada grupo debe entregar:

1. Nombre del bucket S3 y key del ZIP usado.
2. Configuracion Lambda:
   - runtime;
   - handler;
   - timeout;
   - memoria.
3. Resultado de test event valido.
4. Resultado de test event invalido con `400`.
5. Invoke URL de API Gateway y respuesta de `POST /api/delivery`.
6. Captura o texto de CloudWatch Logs.
7. Comparacion breve entre `payment-service` en Swarm y `delivery-service` en Lambda.

---

## Criterios de evaluacion

| Criterio | Excelente | Suficiente | A revisar |
|---|---|---|---|
| Lambda | Handler correcto, eventos validos e invalidos probados | Funcion ejecuta con ayuda | Handler/runtime incorrectos |
| S3 como artefacto | ZIP correcto, bucket privado, key identificada | ZIP cargado pero sin explicar rol de S3 | No logra cargar codigo |
| API Gateway | `POST /api/delivery` funciona publicamente | Funciona con ajustes menores | No llega a Lambda |
| Observabilidad | Usa logs para explicar invocacion y errores | Revisa logs superficialmente | No revisa logs |
| Razonamiento | Compara Swarm vs Lambda con trade-offs | Compara solo por pasos | Confunde contenedor y funcion |
| Limpieza | Elimina API, Lambda, logs y bucket | Limpia parcialmente | Deja recursos activos |

---

## Cierre para discusion

Preguntas:

1. Por que `delivery-service` no necesita una EC2 dedicada?
2. Que ganamos y que perdemos al usar Lambda?
3. Que pasaria si `delivery-service` necesitara conexiones persistentes o procesamiento largo?
4. Como cambia el troubleshooting respecto de Swarm?
5. Conviene que todo sea Lambda? Por que no?

Mensaje final:

```text
Serverless no significa ausencia de arquitectura. Significa delegar el runtime y pagar/operar por invocacion. La decision correcta depende del comportamiento del servicio, no de la moda de la tecnologia.
```
