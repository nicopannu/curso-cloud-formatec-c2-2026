# CloudFormation - Sorny Microservicios

Este folder contiene el template que levanta la infraestructura completa del laboratorio.

La idea no es que memorices CloudFormation. La idea es que puedas levantar un entorno repetible y despues concentrarte en lo importante de la clase: como una aplicacion monolitica empieza a dividir responsabilidades y como cada servicio puede vivir en su propia infraestructura.

## `microservices-sorny-stack.yaml` - template unificado

**Usado en:** Guia Microservicios 01.

**Modelo:**

1. Un frontend muestra seis televisores Sorny con flujo completo de compra.
2. Al inicio, todo `/api/*` va al backend monolitico en su propia EC2.
3. El monolito resuelve catalogo, compra y delivery en un solo proceso.
4. El alumno reconecta rutas hacia servicios separados en sus EC2s dedicadas:
   - `/api/purchases` y `/api/purchases/*` -> `purchase-service`;
   - `/api/delivery` y `/api/delivery/*` -> `delivery-service`;
   - `/api/payments` y `/api/payments/*` -> `payment-service`.
5. `purchase-service` queda con una dependencia mal configurada (`PurchasePaymentServiceUrl` con placeholder `REPLACE-WITH-ALB-DNS`) para que el flujo falle y sea diagnosticable con CloudWatch.

**Crea:**

- 1 ALB publico con listener HTTP `:80`;
- Security Groups: ALB, frontend, monolith, delivery, purchase, payment;
- 5 EC2s Amazon Linux 2023:
  - **EC2-frontend**: frontend (puerto 5000)
  - **EC2-monolith**: monolithic-backend (5001) + maneja `/api/delivery` como fallback monolitico
  - **EC2-delivery**: delivery-service (5005)
  - **EC2-purchase**: purchase-service (5002)
  - **EC2-payment**: payment-service (5004)
- 5 target groups (frontend, monolith, delivery, purchase, payment);
- Reglas base opcionales: `/*` -> frontend, `/api/*` -> monolith (via `DeployMonolito=true` o `CreateBaseAlbRules=true`);
- Reglas microservicio opcionales: purchases, delivery, payments (via `CreateMicroserviceAlbRules=true`);
- CloudWatch Log Group con streams por servicio;
- 5 alarmas de status check EC2.

**No crea:** VPC, subnets, Internet Gateway, route tables, IAM Role ni Instance Profile.

El rol/profile SSM de las EC2 debe existir previamente.

**Parametros clave:**

| Parametro | Uso recomendado |
|---|---|
| `VpcId` | VPC existente del laboratorio |
| `SubnetAId` | Subnet publica para EC2s (us-east-1a) |
| `SubnetBId` | Segunda subnet publica para ALB (us-east-1b) |
| `SsmInstanceProfileName` | Instance Profile existente con SSM y CloudWatch |
| `DeployMonolito` | `true` para levantar sitio + monolito inicial automaticamente al terminar el deploy |
| `CreateBaseAlbRules` | `true` para crear reglas base sin usar DeployMonolito |
| `CreateMicroserviceAlbRules` | `false` para que el alumno cree las reglas manualmente |
| `PurchasePaymentServiceUrl` | Default intencionalmente roto (`REPLACE-WITH-ALB-DNS`); el alumno lo corrige en la Fase 7 |

**Stack name sugerido:**

```text
sorny-microservices-stack
```

## Limpieza

Al finalizar, eliminar las reglas del ALB creadas manualmente (prioridad 10, 20, 30) antes de eliminar el stack para evitar `DELETE_FAILED`. Luego eliminar `sorny-microservices-stack`. No eliminar VPC, subnets ni recursos persistentes del curso.
