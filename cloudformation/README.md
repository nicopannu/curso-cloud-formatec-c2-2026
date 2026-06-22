# CloudFormation - M2-C4 Contenedores y Serverless

Este folder contiene solo los templates necesarios para la clase M2-C4.

La idea no es memorizar CloudFormation. La idea es levantar puntos de partida repetibles para discutir decisiones de arquitectura: Docker manual, Docker Swarm en EC2 y Lambda.

## Referencia por lab

| Lab | Documento principal | CloudFormation asociado | Uso |
|---|---|---|---|
| LAB01 | `guias/guia-contenedores-lab01-docker-local-ec2.md` | `contenedores-lab01-docker-ec2-bootstrap.yaml` | EC2 publica opcional para practicar Docker cuando no se usa Docker local |
| LAB02 | `guias/guia-contenedores-lab02-sorny-docker-swarm.md` | `contenedores-lab02-sorny-swarm-bootstrap.yaml` | ALB, frontend EC2, manager y workers para Docker Swarm |
| LAB03 | `guias/guia-contenedores-lab03-sorny-delivery-lambda.md` | Sin template propio | Lambda/API Gateway/S3 se crean paso a paso por consola para reforzar el modelo serverless |

---

## Templates

| Template | Uso |
|---|---|
| `contenedores-lab01-docker-ec2-bootstrap.yaml` | LAB01 AWS opcional: EC2 publica Amazon Linux 2023 con Docker instalado |
| `contenedores-lab02-sorny-swarm-bootstrap.yaml` | LAB02 bootstrap: ALB publico, frontend EC2, 1 manager y 2 workers EC2 publicos para Docker Swarm |

---

## LAB01 — `contenedores-lab01-docker-ec2-bootstrap.yaml`

**Usado en:** `guias/guia-contenedores-lab01-docker-local-ec2.md` — LAB01 Docker local o EC2 bootstrap.

**Modelo:**

```text
Alumno -> EC2 publica:8080 -> contenedor Docker
```

**Crea:**

- 1 EC2 Amazon Linux 2023;
- 1 Security Group con inbound TCP `8080` desde `AllowedHttpCidr`;
- Docker instalado por UserData;
- salida a internet para descargar imagenes;
- outputs utiles para SSM y pruebas HTTP.

**No crea:** VPC, subnet, IAM role/profile, ALB, ECR ni repositorios.

**Parametros clave:**

| Parametro | Uso recomendado |
|---|---|
| `VpcId` | VPC existente del laboratorio |
| `SubnetId` | Subnet publica con salida a internet |
| `AllowedHttpCidr` | IP/rango autorizado a probar `:8080` |
| `SsmInstanceProfileName` | Instance Profile existente con permisos SSM |

**Stack name sugerido:**

```text
sorny-docker-bootstrap
```

**Outputs importantes:**

- `InstanceId`
- `PublicDnsName`
- `PublicIp`
- `HttpUrl`
- `SsmConnectHint`
- `SecurityGroupId`

---

## LAB02 — `contenedores-lab02-sorny-swarm-bootstrap.yaml`

**Usado en:** `guias/guia-contenedores-lab02-sorny-docker-swarm.md` — LAB02 Docker Swarm. Sirve como arquitectura de partida para `guias/guia-contenedores-lab03-sorny-delivery-lambda.md` — LAB03 Lambda.

**Modelo inicial:**

```text
Usuario
  |
  v
ALB publico
  +-- /*                               -> frontend EC2 publica :5000
  +-- /api/purchases, /api/purchases/* -> workers Swarm :5003
  +-- /api/payments,  /api/payments/*  -> workers Swarm :5004

EC2 publicas con SSM:
  - frontend
  - swarm-manager
  - swarm-worker-1
  - swarm-worker-2
```

**Crea:**

- 1 ALB publico;
- 1 listener HTTP `:80`;
- 1 EC2 frontend con IP publica;
- 1 EC2 manager para Docker Swarm;
- 2 EC2 workers para Docker Swarm;
- Docker instalado en manager y workers;
- Security Group del ALB;
- Security Group del frontend;
- Security Group de Swarm con:
  - puertos `5003` y `5004` para servicios publicados;
  - puertos internos Swarm `2377/tcp`, `7946/tcp`, `7946/udp`, `4789/udp` entre nodos;
- Target Group de frontend;
- Target Group de purchases hacia los dos workers en puerto `5003`;
- Target Group de payments hacia los dos workers en puerto `5004`;
- reglas ALB para `/api/purchases*` y `/api/payments*`.

**No crea:**

- cluster Swarm inicializado;
- servicios Swarm desplegados;
- imagenes Docker copiadas o construidas en los workers;
- registry Docker/ECR;
- Lambda/API Gateway;
- VPC, subnets, NAT, Internet Gateway ni IAM roles compartidos.

Esos pasos quedan a cargo del alumno en las guias, usando AWS Console y SSM Session Manager.

**Parametros clave:**

| Parametro | Uso recomendado |
|---|---|
| `VpcId` | VPC existente del laboratorio |
| `SubnetAId` | Subnet publica para frontend, Swarm manager y worker 1 |
| `SubnetBId` | Subnet publica para Swarm worker 2 y ALB |
| `SsmInstanceProfileName` | Instance Profile existente con SSM |
| `InstanceType` | `t3.micro` para demo, `t3.small` si Docker build queda justo |

**Stack name sugerido:**

```text
sorny-m2c4-swarm
```

**Outputs importantes:**

- `AlbDnsName`
- `AlbUrl`
- `FrontendPublicIp`
- `SwarmManagerInstanceId`
- `SwarmManagerPublicIp`
- `SwarmManagerPrivateIp`
- `SwarmWorker1InstanceId`
- `SwarmWorker1PublicIp`
- `SwarmWorker1PrivateIp`
- `SwarmWorker2InstanceId`
- `SwarmWorker2PublicIp`
- `SwarmWorker2PrivateIp`
- `PurchaseHealthUrl`
- `PaymentHealthUrl`

---

## Limpieza

Para `contenedores-lab01-docker-ec2-bootstrap.yaml`:

1. Eliminar el stack `sorny-docker-bootstrap`.
2. No eliminar VPC, subnets ni roles compartidos.

Para `contenedores-lab02-sorny-swarm-bootstrap.yaml`:

1. En el manager, eliminar primero el stack Swarm:

```bash
docker stack rm sorny
```

2. Si se crearon recursos externos durante LAB03, limpiar:

- API Gateway;
- Lambda;
- bucket S3 de artefactos;
- CloudWatch Log Group de Lambda.

3. Eliminar el stack CloudFormation:

```text
CloudFormation > Stacks > sorny-m2c4-swarm > Delete
```

4. No eliminar VPC, subnets, Internet Gateway, route tables ni roles compartidos del curso.
