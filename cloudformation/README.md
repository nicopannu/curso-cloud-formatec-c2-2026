# CloudFormation - Sorny Microservicios

Este folder contiene el template que levanta la infraestructura base del laboratorio.

La idea no es que memorices CloudFormation. La idea es que puedas levantar un entorno repetible y despues concentrarte en lo importante de la clase: como una aplicacion monolitica empieza a dividir responsabilidades.

## Como leer este folder

Usa `microservices-sorny-stack.yaml` como template unificado del laboratorio.

El template crea la aplicacion Sorny completa: ALB publico, listener HTTP, Security Groups, EC2, frontend, backend monolitico, servicios pequenos, target groups, reglas base, logs y alarma.

## `microservices-sorny-stack.yaml` - template unificado

**Usado en:** Guia Microservicios 01.

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

- 1 ALB publico con listener HTTP `:80`;
- Security Group del ALB con HTTP publico y egress a puertos `5000-5004`;
- 1 EC2 Amazon Linux 2023 con cinco apps:
  - `frontend` en puerto `5000`;
  - `monolithic-backend` en puerto `5001`;
  - `purchase-service` en puerto `5002`;
  - `stock-service` en puerto `5003`;
  - `payment-service` en puerto `5004`;
- Security Group para la EC2 que permite trafico desde el ALB a puertos `5000-5004`;
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

**No crea:**

- VPC;
- subnets publicas/privadas;
- Internet Gateway;
- route tables;
- IAM Role ni Instance Profile.

El rol/profile SSM de la EC2 debe existir previamente en la cuenta del curso.

**Parametros clave:**

| Parametro | Uso recomendado |
|---|---|
| `VpcId` | VPC existente del laboratorio |
| `SubnetAId` | subnet publica para EC2 y ALB |
| `SubnetBId` | segunda subnet publica para ALB |
| `CreateBaseAlbRules` | `true` para levantar sitio + monolito inicial |
| `CreateMicroserviceAlbRules` | `false` para que el alumno cree las reglas |
| `PurchaseStockServiceUrl` | default roto para que `purchase-service` falle al consultar stock |
| `PurchasePaymentServiceUrl` | URL correcta por defecto hacia `payment-service` |
| `ProjectName` | usar `sorny` para nombres de recursos y logs |

**Stack name sugerido:**

```text
sorny-microservices-sorny-stack
```

## Limpieza

Al finalizar, elimina el stack:

```text
sorny-microservices-sorny-stack
```

No elimines VPC, Internet Gateway, subnets, route tables ni roles persistentes del curso si fueron creados para varias clases.
