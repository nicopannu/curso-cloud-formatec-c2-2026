# Sorny Microservices - Formatec Cloud 2026

Repositorio del curso Arquitectura e Ingenieria Cloud | C2.

Profesor Nicolas Pannucio.

## Para que sirve este repositorio

Este repositorio acompana las practicas del curso. Cada branch representa una clase o un caso concreto.

En esta branch trabajamos el paso de un backend monolitico a servicios mas pequenos usando un e-commerce de televisores: **Sorny**.

## Como recorrer el material

1. Lee primero este README para ubicarte.
2. Entra a `guias/` para seguir la consigna.
3. Entra a `cloudformation/` solo cuando necesites levantar o revisar infraestructura.

Este orden importa porque primero hay que entender el objetivo tecnico. CloudFormation resuelve el arranque, pero no reemplaza el razonamiento de arquitectura.

## Branches

Cada practica tiene su propia branch. Clona el repo o cambia a la branch correspondiente antes de empezar:

| Branch | Contenido |
|---|---|
| `main` | Documentacion general y estructura base del repo |
| `m2-c1-lab` | Modulo 2 - Clase 1: REHOST + REPLATFORM |
| `m2-c2-lab` | Modulo 2 - Clase 2: escalabilidad y alta disponibilidad |
| `m2-c3-lab` | Modulo 2 - Clase 3: monolito a microservicios con Sorny |

```bash
git clone https://github.com/nicopannu/curso-cloud-formatec-c2-2026.git
cd curso-cloud-formatec-c2-2026

git checkout m2-c3-lab
```

## Que vas a construir en esta branch

Vas a partir de una aplicacion funcional desplegada en 3 EC2s:

```text
frontend (EC2-frontend) -> backend monolitico (EC2-monolith) -> estado local
```

El frontend muestra seis televisores Sorny. El cliente selecciona uno, completa la compra y deja datos de contacto. El backend monolitico lo resuelve todo en un solo proceso.

Luego vas a dividir el backend en servicios independientes con su propia EC2:

- **EC2-frontend**: frontend (la tienda)
- **EC2-monolith**: monolith + delivery (el backend original)
- **EC2-services**: purchase + stock + payment (microservicios separados)

El objetivo es ver que al dividir responsabilidades tambien aparecen contratos, rutas, dependencias, logs y fallas parciales entre servicios que viven en servidores distintos.

## Archivos principales

| Ruta | Uso |
|---|---|
| `guias/guia-microservicios-01-sorny-monolito-microservicios.md` | Guia principal para el alumno |
| `cloudformation/README.md` | Guia del folder de infraestructura |
| `cloudformation/microservices-sorny-stack.yaml` | Stack unificado que levanta ALB, 3 EC2s y servicios |

## Resultado esperado

Al terminar, deberias poder explicar:

- por que compras, stock y pagos son responsabilidades separables;
- que cambia en el ALB cuando una ruta deja de ir al monolito;
- por que un flujo puede fallar aunque todos los servicios parezcan "up";
- como CloudWatch ayuda a encontrar el punto exacto de falla;
- que diferencias de networking aparecen cuando los servicios estan en distintas EC2s;
- que decisiones faltarian antes de llevar esto a produccion.

Proyecto educativo - Formatec Cloud Course 2026.