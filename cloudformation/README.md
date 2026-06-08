# CloudFormation - Microservicios (M2C3)

Templates de bootstrap para el laboratorio de microservicios.

El objetivo de estos stacks es preparar infraestructura y aplicaciones demo para que el alumno se concentre en:

- separacion de responsabilidades;
- ALB path routing;
- target groups por servicio;
- health checks;
- CloudWatch;
- comunicacion entre servicios.

## `microservices-lab-prereqs.yaml` - helper docente temporal

**Uso recomendado:** solo para pruebas del docente cuando la cuenta todavia no tiene ALB ni instance profile listos.

No es parte del recorrido del alumno. Para la clase, las subnets publicas/privadas del curso deberian quedar creadas como pre-requisito persistente.

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
cloudcuyo-microservices-prereqs
```

Si se usa para validar el lab, usar los outputs `AlbSecurityGroupId`, `AlbListenerArn` y `SsmInstanceProfileName` como parametros del stack `microservices-site-bootstrap.yaml`, y luego eliminarlo.

---

## `microservices-site-bootstrap.yaml` - recomendado

**Usado en:** Guia Microservicios 02.

**Modelo del lab:**

1. Un frontend sirve el sitio CloudCuyo.
2. Inicialmente todo `/api/*` va al backend monolitico.
3. El alumno divide rutas hacia backends mas chicos:
   - `/api/catalog/*`,
   - `/api/auth/*`,
   - `/api/profile/*`.
4. `profile-service` tiene una comunicacion rota contra `auth-service` para investigar con CloudWatch.

**Crea:**

- 1 EC2 Amazon Linux 2023 con cinco apps demo:
  - `frontend` en puerto `5000`,
  - `monolithic-backend` en puerto `5001`,
  - `catalog-service` en puerto `5002`,
  - `auth-service` en puerto `5003`,
  - `profile-service` en puerto `5004`;
- Security Group para la EC2;
- target groups por app;
- reglas base opcionales:
  - `/*` -> frontend,
  - `/api/*` -> monolith;
- reglas microservicio opcionales:
  - `/api/catalog/*`,
  - `/api/auth/*`,
  - `/api/profile/*`;
- CloudWatch Log Group;
- alarma base de status check EC2.

**Parametros clave:**

| Parametro | Uso recomendado |
|---|---|
| `CreateBaseAlbRules` | `true` para levantar sitio + monolito inicial |
| `CreateMicroserviceAlbRules` | `false` para que el alumno cree las reglas durante el lab |
| `ProfileAuthValidateUrl` | default roto para que `profile-service` falle y se investigue con CloudWatch |

**Stack name sugerido:**

```text
cloudcuyo-microservices-site-bootstrap
```

## Limpieza

Eliminar el stack `cloudcuyo-microservices-site-bootstrap` al finalizar el lab.

Si se uso el stack de pre-requisitos solo para esta clase, eliminar primero `cloudcuyo-microservices-site-bootstrap` y despues `cloudcuyo-microservices-prereqs`.

No eliminar VPC, Internet Gateway, subnets ni route tables persistentes del curso.
