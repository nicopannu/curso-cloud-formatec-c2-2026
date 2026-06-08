# CloudFormation - Sorny Microservicios

Este folder contiene los templates que levantan la infraestructura base.

La idea no es que memorices CloudFormation. La idea es que puedas levantar un entorno repetible y despues concentrarte en lo importante de la clase: como una aplicacion monolitica empieza a dividir responsabilidades.

## Como leer este folder

Usa este orden:

1. `microservices-site-bootstrap.yaml`: template principal.
2. `microservices-lab-prereqs.yaml`: helper temporal si la cuenta todavia no tiene ALB, listener o instance profile.

El template principal crea la aplicacion Sorny: frontend, backend monolitico y servicios pequenos. El helper solo existe para no trabar una practica cuando faltan prerequisitos de infraestructura.

## `microservices-site-bootstrap.yaml` - template principal

**Usado en:** Guia Microservicios 02.

**Modelo:**

1. Un frontend muestra seis televisores Sorny.
2. Al inicio, todo `/api/*` va al backend monolitico.
3. El monolito resuelve catalogo, compra, stock y pago en un solo proceso.
4. El alumno reconecta rutas hacia servicios separados:
   - `/api/purchases/*` -> `purchase-service`;
   - `/api/stock/*` -> `stock-service`;
   - `/api/payments/*` -> `payment-service`.
5. `purchase-service` queda con una dependencia mal configurada para que el flujo falle y el alumno diagnostique con CloudWatch.

Esta falla es intencional. En microservicios reales, muchas fallas no ocurren porque el servidor este apagado, sino porque una pieza llama a otra con una URL, puerto, ruta, timeout o contrato incorrecto.

**Crea:**

- 1 EC2 Amazon Linux 2023 con cinco apps:
  - `frontend` en puerto `5000`;
  - `monolithic-backend` en puerto `5001`;
  - `purchase-service` en puerto `5002`;
  - `stock-service` en puerto `5003`;
  - `payment-service` en puerto `5004`;
- Security Group para la EC2;
- target groups por app;
- reglas base opcionales:
  - `/*` -> frontend;
  - `/api/*` -> monolith;
- reglas microservicio opcionales:
  - `/api/purchases/*`;
  - `/api/stock/*`;
  - `/api/payments/*`;
- CloudWatch Log Group;
- alarma base de status check EC2.

**Parametros clave:**

| Parametro | Uso recomendado |
|---|---|
| `CreateBaseAlbRules` | `true` para levantar sitio + monolito inicial |
| `CreateMicroserviceAlbRules` | `false` para que el alumno cree las reglas |
| `PurchaseStockServiceUrl` | default roto para que `purchase-service` falle al consultar stock |
| `PurchasePaymentServiceUrl` | URL correcta por defecto hacia `payment-service` |
| `ProjectName` | usar `sorny` para nombres de recursos y logs |

**Stack name sugerido:**

```text
sorny-microservices-site-bootstrap
```

## `microservices-lab-prereqs.yaml` - helper docente temporal

**Uso recomendado:** solo para pruebas del docente cuando la cuenta todavia no tiene ALB ni instance profile listos.

No es parte del recorrido principal del alumno. Para clase, la VPC, subnets, ALB, listener e instance profile deberian quedar preparados como prerequisitos persistentes.

**Crea:**

- ALB publico;
- listener HTTP `:80`;
- Security Group del ALB;
- IAM Role + Instance Profile para EC2 con SSM y CloudWatch Agent.

**No crea:**

- VPC;
- subnets publicas/privadas;
- Internet Gateway;
- route tables.

**Stack name sugerido:**

```text
sorny-microservices-prereqs
```

Si se usa para validar el entorno, tomar los outputs `AlbSecurityGroupId`, `AlbListenerArn` y `SsmInstanceProfileName` como parametros del stack principal.

## Limpieza

Al finalizar, elimina primero:

```text
sorny-microservices-site-bootstrap
```

Si tambien usaste el helper docente, elimina despues:

```text
sorny-microservices-prereqs
```

No elimines VPC, Internet Gateway, subnets ni route tables persistentes del curso si fueron creados para varias clases.
