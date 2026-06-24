# M2-C4 - Contenedores y Serverless

Repositorio de la clase M2-C4 del curso Arquitectura e Ingenieria Cloud | C2.

Profesor Nicolas Pannucio.

## Proposito de esta branch

Esta branch contiene solamente el material necesario para la clase de contenedores y serverless.

El caso usado es Sorny. El foco de esta clase es comparar modelos de ejecucion:

```text
Docker local o EC2 bootstrap -> imagenes y contenedores
Docker Swarm en EC2          -> servicios replicados sobre VMs propias
AWS Lambda                   -> funcion stateless por evento HTTP
```

## Recorrido recomendado

1. Empezar por LAB01 para instalar/probar Docker.
2. Si no se puede instalar Docker localmente, usar el bootstrap EC2 de AWS del LAB01.
3. Seguir con LAB02 para desplegar `purchase-service` y `payment-service` en Docker Swarm.
4. Cerrar con LAB03 para llevar `delivery-service` a Lambda.

La idea no es memorizar pantallas de consola. La idea es decidir que modelo de ejecucion conviene para cada responsabilidad.

## Documentos del laboratorio

| Lab | Documento | Foco |
|---|---|---|
| LAB01 | `guias/guia-contenedores-lab01-docker-local-ec2.md` | Fundamentos Docker: Windows + WSL2/Docker Desktop o EC2 bootstrap |
| LAB02 | `guias/guia-contenedores-lab02-sorny-docker-swarm.md` | Migracion de `purchase-service` y `payment-service` a Docker Swarm en EC2 |
| LAB03 | `guias/guia-contenedores-lab03-sorny-delivery-lambda.md` | Migracion de `delivery-service` a Lambda + API Gateway |

## CloudFormation

| Lab | Template | Uso |
|---|---|---|
| LAB01 | `cloudformation/contenedores-lab01-docker-ec2-bootstrap.yaml` | EC2 publica Amazon Linux 2023 con Docker instalado para quienes no usen Docker local |
| LAB02 | `cloudformation/contenedores-lab02-sorny-swarm-bootstrap.yaml` | ALB publico, frontend EC2, 1 manager y 2 workers para Docker Swarm |
| LAB03 | Sin template propio | Se implementa paso a paso por consola: S3, Lambda, API Gateway y CloudWatch Logs |

## Artefactos de aplicacion

Durante LAB01 y LAB02 no se copian Dockerfiles a mano desde la guia. Las EC2 descargan el paquete versionado de la branch `m2-c4`:

```bash
LAB_DIR="$HOME/m2-c4-lab"
mkdir -p "$LAB_DIR"
cd "$LAB_DIR"

curl -L -o m2-c4.tar.gz \
  https://github.com/nicopannu/curso-cloud-formatec-c2-2026/archive/refs/heads/m2-c4.tar.gz
```

Esto mantiene trazabilidad: `Dockerfile`, codigo fuente y `docker-stack.yml` viajan juntos.

| Ruta | Uso |
|---|---|
| `apps/docker-hostinfo/` | App Flask + Dockerfile para construir imagen `sorny-hostinfo:v1` en LAB01 |
| `apps/sorny-swarm/` | Apps, Dockerfiles y `docker-stack.yml` para `purchase-service` y `payment-service` en Swarm |
| `lambda/sorny-delivery-lambda/app.py` | Codigo fuente del handler Lambda de delivery |
| `lambda/sorny-delivery-lambda/sorny-delivery-lambda.zip` | ZIP listo para subir a S3 y cargar en Lambda |

## Arquitectura objetivo

```text
Usuario
  |
  v
ALB publico
  |
  +-- /*                               -> frontend EC2
  +-- /api/purchases, /api/purchases/* -> Docker Swarm workers :5003
  +-- /api/payments,  /api/payments/*  -> Docker Swarm workers :5004

Docker Swarm:
  - swarm-manager: administra el cluster, no recibe trafico de aplicacion
  - swarm-worker-1: ejecuta servicios
  - swarm-worker-2: ejecuta servicios

Serverless:
  - delivery-service -> Lambda + API Gateway
```

## Resultado esperado

Al terminar, deberias poder explicar:

- que problema resuelve una imagen Docker frente a instalar dependencias manualmente;
- como correr varios contenedores de una misma imagen y por que eso no equivale a un servicio escalable;
- que diferencia hay entre Docker Engine manual y Docker Swarm;
- por que Swarm permite declarar servicios, replicas y recuperacion ante fallas simples;
- que rol cumple el ALB frente al cluster Swarm;
- por que `delivery-service` puede ser una funcion Lambda;
- como S3 puede usarse como repositorio de artefactos ZIP para Lambda;
- que trade-offs aparecen entre VM, contenedor orquestado y serverless.

## Limpieza

Los recursos AWS creados durante la clase deben eliminarse al terminar:

- stacks CloudFormation;
- Lambda;
- API Gateway;
- bucket S3 usado para el ZIP;
- log groups si no se necesitan.

No eliminar VPC, subnets, roles ni recursos compartidos del curso.
