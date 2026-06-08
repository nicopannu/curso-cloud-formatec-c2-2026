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

Vas a partir de una aplicacion funcional:

```text
frontend -> backend monolitico -> base de datos/estado local del backend
```

El frontend muestra seis televisores Sorny. El cliente selecciona uno y el backend monolitico:

1. recibe la solicitud de compra;
2. revisa si hay stock;
3. genera un enlace de pago;
4. devuelve ese enlace al frontend;
5. el frontend muestra una pantalla de pago.

Luego vas a dividir el backend en servicios:

- `purchase-service`: recibe la compra y coordina el flujo;
- `stock-service`: valida y reserva inventario;
- `payment-service`: genera el enlace de pago.

El objetivo es ver que al dividir responsabilidades tambien aparecen contratos, rutas, dependencias, logs y fallas parciales.

## Archivos principales

| Ruta | Uso |
|---|---|
| `guias/guia-microservicios-02-lab-aws-descomposicion.md` | Guia principal para el alumno |
| `cloudformation/README.md` | Guia del folder de infraestructura |
| `cloudformation/microservices-site-bootstrap.yaml` | Stack que levanta frontend, monolito y servicios |
| `cloudformation/microservices-lab-prereqs.yaml` | Stack auxiliar docente para ALB/roles si la cuenta no los tiene |

## Resultado esperado

Al terminar, deberias poder explicar:

- por que compras, stock y pagos son responsabilidades separables;
- que cambia en el ALB cuando una ruta deja de ir al monolito;
- por que un flujo puede fallar aunque todos los servicios parezcan "up";
- como CloudWatch ayuda a encontrar el punto exacto de falla;
- que decisiones faltarian antes de llevar esto a produccion.

Proyecto educativo - Formatec Cloud Course 2026.
