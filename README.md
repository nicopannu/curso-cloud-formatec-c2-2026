# Contenedores y Serverless - Formatec Cloud 2026

Repositorio del curso Arquitectura e Ingenieria Cloud | C2.

Profesor Nicolas Pannucio.

## Para que sirve este repositorio

Este repositorio acompana las practicas del curso. Cada branch representa una clase o un caso concreto.

En esta branch continuamos con Sorny despues del lab de microservicios. Primero usamos Docker para entender imagenes y contenedores. Despues migramos dos APIs Sorny a Docker Swarm sobre 1 manager y 2 workers EC2 publicos y dejamos una tercera API como Lambda para comparar modelos de ejecucion.

## Como recorrer el material

1. Lee este README para ubicarte.
2. Empeza por la Guia A de fundamentos Docker.
3. Usa el bootstrap Sorny M2-C4 para levantar ALB, frontend EC2 y 1 manager y 2 workers Swarm publicos.
4. Segui con Guia B1 para migrar `purchase-service` y `payment-service` a Docker Swarm.
5. Segui con Guia B2 para llevar `delivery-service` a Lambda.

La idea no es memorizar pantallas de consola. La idea es decidir que modelo de ejecucion conviene para cada responsabilidad.

## Branches

Cada practica tiene su propia branch:

| Branch | Contenido |
|---|---|
| `main` | Documentacion general y estructura base del repo |
| `m2-c1-lab` | Modulo 2 - Clase 1: migracion inicial y razonamiento de arquitectura |
| `m2-c2-lab` | Modulo 2 - Clase 2: escalabilidad y alta disponibilidad |
| `m2-c3-lab` | Modulo 2 - Clase 3: monolito a microservicios con Sorny |
| `m2-c4-contenedores-serverless` | Modulo 2 - Clase 4: Docker, Docker Swarm y Lambda |

```bash
git clone https://github.com/nicopannu/curso-cloud-formatec-c2-2026.git
cd curso-cloud-formatec-c2-2026

git checkout m2-c4-contenedores-serverless
```

## Guias principales

| Ruta | Uso |
|---|---|
| `guias/guia-contenedores-01-docker-local-ec2.md` | Guia A: Docker local con Windows/WSL2 si se puede, o EC2 bootstrap como alternativa. Construye una imagen que saluda con hostname e IP |
| `guias/guia-contenedores-02-sorny-docker-swarm.md` | Guia B1: migrar `purchase-service` y `payment-service` de Sorny a Docker Swarm en 1 manager y 2 workers EC2 publicos |
| `guias/guia-serverless-01-sorny-delivery-lambda.md` | Guia B2: llevar `delivery-service` de Sorny a Lambda, subiendo ZIP a S3 |
| `guias/guia-microservicios-01-sorny-monolito-microservicios.md` | Antecedente M2-C3 para entender el caso Sorny original |

## Templates CloudFormation

| Ruta | Uso |
|---|---|
| `cloudformation/docker-ec2-bootstrap.yaml` | Opcion B de Guia A: EC2 publica Amazon Linux 2023 con Docker instalado |
| `cloudformation/sorny-microservices-m2c4-bootstrap.yaml` | Bootstrap de Guia B: ALB publico, frontend EC2 y 1 manager y 2 workers EC2 publicos para Docker Swarm |
| `cloudformation/microservices-sorny-stack.yaml` | Template original M2-C3, mantenido como antecedente |

## Artefactos de apoyo

| Ruta | Uso |
|---|---|
| `apps/docker-hostinfo/` | App Flask + Dockerfile para construir imagen `sorny-hostinfo:v1` |
| `apps/sorny-swarm/` | Apps, Dockerfiles y `docker-stack.yml` para `purchase-service` y `payment-service` en Swarm |
| `lambda/sorny-delivery-lambda/app.py` | Codigo fuente del handler Lambda de delivery |
| `lambda/sorny-delivery-lambda/sorny-delivery-lambda.zip` | ZIP listo para subir a S3 y cargar en Lambda |

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

Proyecto educativo - Formatec Cloud Course 2026.
