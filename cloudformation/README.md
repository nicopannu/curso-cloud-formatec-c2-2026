# CloudFormation - Sorny Microservicios

Este folder contiene el template que levanta la infraestructura completa del laboratorio.

La idea no es que memorices CloudFormation. La idea es que puedas levantar un entorno repetible y despues concentrarte en lo importante de la clase: como una aplicacion monolitica empieza a dividir responsabilidades y como cada servicio puede vivir en su propia infraestructura.

## `microservices-sorny-stack.yaml` - template unificado

**Usado en:** Guia Microservicios 01.

**Modelo:**

1. Un frontend muestra seis televisores Sorny con flujo completo de compra.
2. Al inicio, todo `/api/*` va al backend monolitico en su propia EC2.
3. El monolito resuelve catalogo, compra, stock, pago y delivery en un solo proceso.
4. El alumno reconecta rutas hacia servicios separados en `EC2-services`:
   - `/api/purchases/*` -> `purchase-service`;
   - `/api/stock/*` -> `stock-service`;
   - `/api/payments/*` -> `payment-service`.
5. `purchase-service` queda con una dependencia mal configurada para que el flujo falle.

**Crea:**

- 1 ALB publico con listener HTTP `:80`;
- Security Groups: ALB, frontend, monolith, services;
- 3 EC2s Amazon Linux 2023:
  - **EC2-frontend**: frontend (puerto 5000)
  - **EC2-monolith**: monolithic-backend (5001) + delivery-service (5005)
  - **EC2-services**: purchase (5002) + stock (5003) + payment (5004)
- 6 target groups (frontend, monolith, delivery, purchase, stock, payment);
- Reglas base opcionales: `/*` -> frontend, `/api/*` -> monolith;
- Reglas microservicio opcionales: `/api/purchases/*`, `/api/stock/*`, `/api/payments/*`;
- CloudWatch Log Group con streams por servicio;
- 3 alarmas de status check EC2.

**No crea:** VPC, subnets, Internet Gateway, route tables, IAM Role ni Instance Profile.

El rol/profile SSM de las EC2 debe existir previamente.

**Parametros clave:**

| Parametro | Uso recomendado |
|---|---|
| `VpcId` | VPC existente del laboratorio |
| `SubnetAId` | Subnet publica para EC2s |
| `SubnetBId` | Segunda subnet publica para ALB |
| `SsmInstanceProfileName` | Instance Profile existente con SSM y CloudWatch |
| `CreateBaseAlbRules` | `true` para levantar sitio + monolito inicial |
| `CreateMicroserviceAlbRules` | `false` para que el alumno cree reglas |
| `PurchaseStockServiceUrl` | Default roto (puerto 5999, intencional) |
| `PurchasePaymentServiceUrl` | URL correcta hacia payment-service |

**Stack name sugerido:**

```text
sorny-microservices-stack
```

## Limpieza

Al finalizar, eliminar `sorny-microservices-stack`. No eliminar VPC, subnets ni recursos persistentes del curso.