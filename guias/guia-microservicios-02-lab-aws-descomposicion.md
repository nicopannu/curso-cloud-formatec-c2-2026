# Guia Microservicios 02: De monolito a servicios pequenos en AWS

## Objetivo

Descomponer una aplicacion monolitica de CloudCuyo en aplicaciones mas pequenas, con una progresion de tres ejercicios:

1. separar un primer servicio simple y observarlo con CloudWatch;
2. agregar login/autenticacion como servicio separado;
3. introducir comunicacion entre servicios y analizar fallas.

El laboratorio esta pensado para alumnos de nivel intermedio con conocimientos todavia incompletos. Por eso avanza de lo basico a lo avanzado, sin asumir experiencia profunda en microservicios.

## Desafio del laboratorio

CloudCuyo tiene un monolito funcionando. El desafio es separar capacidades en servicios mas chicos sin romper la aplicacion, manteniendo ruteo, observabilidad y una comunicacion minima entre servicios.

Consigna:

> Descompongan el monolito CloudCuyo en servicios mas pequenos usando EC2 + ALB. Mantengan el portal funcionando, separen catalogo y login, hagan que perfil valide identidad contra auth-service, y demuestren con CloudWatch que parte del sistema esta sana o fallando.

El bootstrap resuelve la plomeria inicial. El alumno debe concentrarse en:

- que responsabilidad separa cada servicio;
- como enruta el ALB;
- como se valida que cada servicio esta sano;
- como se observa cada pieza en CloudWatch;
- que pasa cuando un servicio depende de otro;
- que complejidad aparece al pasar de monolito a servicios separados.

## Duracion estimada

2 a 3 horas.

## Enfoque de modernización

No se busca rehacer todo CloudCuyo. Se busca partir una aplicacion grande en piezas mas pequenas de forma controlada y observar que problemas aparecen.

## Mensaje central

> Microservicios no significa "muchas aplicaciones". Significa separar responsabilidades, enrutar bien, observar cada parte y entender como se comunican.

## Contexto

CloudCuyo tiene una aplicacion monolitica que resuelve todo dentro del mismo backend:

- pagina principal,
- login,
- perfil de usuario,
- catalogo,
- mensajes,
- dashboard.

El equipo quiere empezar a dividirla en aplicaciones mas chicas. La separacion se hace gradualmente para que el alumno vea el camino y no solo el resultado final.

## Arquitectura inicial

```text
Usuario
  |
  v
ALB
  |
  +-- /      -> frontend
  |
  +-- /api/* -> backend monolitico
                  |
                  +-- /api/auth/login
                  +-- /api/profile/me
                  +-- /api/catalog/products
```

Problema:

Todo vive junto. Si cambia login, perfil o catalogo, se toca el mismo backend. Si algo falla, cuesta saber que modulo fallo.

## Arquitectura final esperada

```text
Usuario
  |
  v
ALB
  |
  +-- /                 -> frontend
  |
  +-- /api/*            -> backend monolitico (fallback inicial)
  |
  +-- /api/catalog/*        -> catalog-service
  |
  +-- /api/auth/*           -> auth-service
  |
  +-- /api/profile/*        -> profile-service

profile-service
  |
  +-- llama a auth-service /api/auth/validate
```

Servicios:

| Servicio | Responsabilidad | Nivel |
|---|---|---|
| `frontend` | Sitio CloudCuyo; consume `/api/*` | base |
| `monolithic-backend` | Backend inicial que responde todas las APIs | base |
| `catalog-service` | Primer servicio chico, simple y observable | ejercicio 1 |
| `auth-service` | Login, token demo y validacion | ejercicio 2 |
| `profile-service` | Perfil; consume validacion de auth | ejercicio 3 |

## Componentes AWS

Version simple:

- Application Load Balancer.
- Target groups por servicio.
- EC2 para ejecutar los servicios.
- Security Groups.
- CloudWatch Logs.
- CloudWatch Metrics del ALB y de EC2.
- CloudWatch Alarms para detectar comportamiento anomalo.

Opciones de despliegue:

- **Opcion pedagogica ideal:** una EC2 por servicio.
- **Opcion economica/demo:** una EC2 con varios servicios en puertos distintos, pero target groups separados por puerto.

Para alumnos iniciales, la segunda opcion puede ser mas simple y barata. Lo importante es que cada servicio tenga endpoint, health check y logs propios.

## Que levanta el bootstrap y que hace el alumno

El stack CloudFormation de bootstrap prepara la base para no perder la clase en instalacion de dependencias.

### Bootstrap

Levanta:

- una EC2 demo;
- cinco aplicaciones pequenas como procesos separados: frontend, backend monolitico, catalog, auth y profile;
- puertos separados;
- target groups separados;
- CloudWatch Logs;
- alarma base de EC2.

Puede crear reglas del ALB automaticamente, pero para clase conviene usar:

```text
CreateBaseAlbRules=true
CreateMicroserviceAlbRules=false
```

Asi el sitio queda funcionando contra el backend monolitico y el alumno crea las reglas de division durante el laboratorio.

### Alumno

El alumno debe:

- entender que responsabilidad tiene cada app;
- crear o revisar reglas path-based del ALB;
- probar cada endpoint;
- mirar health checks;
- mirar CloudWatch;
- simular una falla;
- explicar que parte cambio a nivel aplicacion y que parte cambio a nivel infraestructura.

### Una EC2 o varias EC2

La version de bootstrap usa una EC2 con servicios separados por proceso y puerto.

Esto no intenta simular produccion perfecta. Es una decision pedagogica para que el alumno vea microservicios sin sumar Docker, ECS, EKS, Lambda ni multiples despliegues.

La separacion se observa por:

- rutas distintas,
- target groups distintos,
- health checks distintos,
- logs distintos,
- responsabilidades distintas.

En una version mas avanzada, cada servicio podria correr en su propia EC2 o en contenedores.

### Decision pedagogica de computo

En este lab usamos **EC2** como herramienta de computo.

No usamos Docker, ECS, EKS, Lambda ni serverless para implementar los servicios, porque todavia no forman parte del recorrido practico del curso.

La idea es que el alumno aprenda microservicios sin cambiar demasiadas variables a la vez:

- mismo modelo de compute que ya conoce,
- mismo ALB que ya vio,
- nuevos target groups por servicio,
- nuevos health checks por servicio,
- CloudWatch para entender monitoreo y automatizacion.

## Rol de CloudWatch en el lab

CloudWatch no aparece solo para "mirar logs". Aparece para mostrar por que monitoreo es obligatorio cuando una aplicacion se divide en partes mas chicas.

Objetivos con CloudWatch:

1. Ver logs separados por servicio.
2. Entender metricas del ALB por target group.
3. Detectar si un servicio chico falla aunque el monolito siga funcionando.
4. Crear una alarma simple sobre comportamiento anomalo.
5. Discutir que automatizaciones podrian dispararse desde esa alarma.

Ejemplos de senales:

- `HTTPCode_Target_5XX_Count`.
- `UnHealthyHostCount`.
- `TargetResponseTime`.
- errores en logs del servicio.

Automatizaciones posibles para discutir:

- notificar al equipo,
- reiniciar un servicio,
- sacar una instancia de rotacion,
- activar rollback de routing,
- disparar investigacion operativa.

No hace falta automatizar todo en la primera version del lab. Alcanza con que el alumno entienda que en microservicios ya no alcanza con saber si "la aplicacion" esta arriba: hay que saber que servicio esta sano, degradado o caido.

## Estructura progresiva

### Ejercicio 1 - Basico: separar una aplicacion chica y verla en CloudWatch

Objetivo:

Separar `catalog-service` desde el monolito y observarlo.

Arquitectura:

```text
ALB
  |
  +-- /          -> frontend
  +-- /api/*     -> backend monolitico
  +-- /api/catalog/* -> catalog-service
```

Endpoints:

```text
GET /api/catalog/health
GET /api/catalog/products
```

Respuesta ejemplo:

```json
{
  "service": "catalog-service",
  "items": [
    "Migracion Cloud",
    "Alta Disponibilidad",
    "Microservicios"
  ]
}
```

Tareas:

1. Identificar que `catalog` es una responsabilidad separable.
2. Crear o iniciar `catalog-service`.
3. Crear target group `tg-catalog-service`.
4. Configurar health check `/api/catalog/health`.
5. Configurar regla ALB:

```text
IF path /api/catalog/* -> tg-catalog-service
fallback /api/*       -> tg-monolithic-backend
```

6. Probar:

```bash
curl http://<alb-dns>/
curl http://<alb-dns>/api/catalog/products
curl http://<alb-dns>/api/catalog/health
```

7. Revisar CloudWatch:

- logs del servicio,
- metricas del target group,
- respuestas 2xx/4xx/5xx en ALB,
- estado del health check.
8. Crear o discutir una alarma simple:

```text
UnHealthyHostCount > 0 para tg-catalog-service
```

o:

```text
HTTPCode_Target_5XX_Count > 0 para tg-catalog-service
```

Preguntas:

- Que cambio respecto del monolito?
- Como se ve en CloudWatch que ahora hay una pieza separada?
- Que pasa si `catalog-service` falla?
- Que podria automatizarse si CloudWatch detecta esa falla?

Resultado esperado:

El alumno entiende la primera separacion sin meter todavia autenticacion ni comunicacion entre servicios.

### Ejercicio 2 - Intermedio: separar login como `auth-service`

Objetivo:

Separar login/autenticacion en un servicio propio.

Arquitectura:

```text
ALB
  |
  +-- /          -> frontend
  +-- /api/*     -> backend monolitico
  +-- /api/catalog/* -> catalog-service
  +-- /api/auth/*    -> auth-service
```

Endpoints:

```text
GET  /api/auth/health
POST /api/auth/login
POST /api/auth/validate
```

Login request:

```json
{
  "username": "nico",
  "password": "cloud123"
}
```

Login response:

```json
{
  "access_token": "demo-token-nico",
  "token_type": "Bearer",
  "expires_in": 3600
}
```

Validate request:

```json
{
  "token": "demo-token-nico"
}
```

Validate response:

```json
{
  "active": true,
  "user": {
    "id": "usr-001",
    "username": "nico",
    "role": "student"
  }
}
```

Tareas:

1. Crear o iniciar `auth-service`.
2. Crear target group `tg-auth-service`.
3. Configurar health check `/api/auth/health`.
4. Configurar regla ALB:

```text
IF path /api/auth/* -> tg-auth-service
```

5. Probar login:

```bash
curl -X POST http://<alb-dns>/api/auth/login \
  -H "Content-Type: application/json" \
  -d '{"username":"nico","password":"cloud123"}'
```

6. Revisar logs de login en CloudWatch.

Preguntas:

- Por que login es buen candidato para separarse?
- Que riesgos aparecen al separar autenticacion?
- Que datos no deberian aparecer en logs?
- Que seria distinto si usaramos Cognito?

Resultado esperado:

El alumno entiende que separar login no es solo mover un endpoint: aparece seguridad, token, logs sensibles y contrato.

### Ejercicio 3 - Avanzado: comunicacion entre servicios

Objetivo:

Agregar `profile-service` y hacer que valide identidad usando `auth-service`.

Arquitectura:

```text
ALB
  |
  +-- /api/profile/* -> profile-service

profile-service
  |
  +-- POST /api/auth/validate -> auth-service
```

Endpoint:

```text
GET /api/profile/me
```

Request:

```http
GET /api/profile/me
Authorization: Bearer demo-token-nico
```

Comportamiento esperado:

1. `profile-service` recibe el token.
2. `profile-service` llama a `auth-service /api/auth/validate`.
3. Si el token es valido, devuelve perfil.
4. Si el token es invalido, devuelve `401`.
5. Si `auth-service` esta caido, devuelve error controlado.

En el bootstrap recomendado, esta comunicacion empieza intencionalmente mal configurada para que el alumno use CloudWatch:

```text
AUTH_VALIDATE_URL=http://127.0.0.1:5999/api/auth/validate
```

El valor correcto es:

```text
AUTH_VALIDATE_URL=http://127.0.0.1:5003/api/auth/validate
```

El objetivo no es memorizar puertos. El objetivo es leer logs, entender la dependencia y corregir la configuracion.

Response:

```json
{
  "user_id": "usr-001",
  "username": "nico",
  "plan": "cloud-student",
  "validated_by": "auth-service"
}
```

Tareas:

1. Crear o iniciar `profile-service`.
2. Crear target group `tg-profile-service`.
3. Configurar health check `/api/profile/health`.
4. Configurar regla ALB:

```text
IF path /api/profile/* -> tg-profile-service
```

5. Probar:

```bash
curl http://<alb-dns>/api/profile/me \
  -H "Authorization: Bearer demo-token-nico"
```

6. Revisar logs:

- request recibido por profile,
- llamada interna a auth,
- resultado de validacion,
- error si auth no responde.

7. Simular falla:

- detener `auth-service`, o
- bloquear temporalmente la comunicacion,
- observar que pasa con `/api/profile/me`.

Preguntas:

- Que servicio depende de cual?
- Que pasa si `auth-service` cae?
- Es bueno validar token llamando a auth en cada request?
- Que alternativa ofrece JWT autocontenido?
- Como se observaria esta dependencia en CloudWatch?

Resultado esperado:

El alumno ve que microservicios introducen comunicacion, latencia, fallas parciales y necesidad de observabilidad.

## Discusion tecnica: comunicacion entre servicios

### Opcion A: llamada sincrona directa

`profile-service -> auth-service /api/auth/validate`

Ventajas:

- facil de entender,
- sirve para clase,
- muestra dependencia real.

Desventajas:

- agrega latencia,
- si auth cae, profile se degrada,
- puede crear acoplamiento fuerte.

### Opcion B: token autocontenido

`profile-service` valida un JWT con clave publica.

Ventajas:

- menos llamadas entre servicios,
- mejor resiliencia,
- menor latencia.

Desventajas:

- mas complejo,
- requiere manejar claves, expiracion y revocacion.

### Opcion C: sesion centralizada

`profile-service` consulta una sesion en Redis o base compartida.

Ventajas:

- modelo conocido,
- revocacion simple.

Desventajas:

- dependencia compartida,
- riesgo de recrear el monolito con otra forma.

Para este lab se usa **Opcion A** porque es la mas clara para ver comunicacion entre servicios.

## Entregables

Cada grupo entrega:

1. Diagrama inicial del monolito.
2. Diagrama final con servicios separados.
3. Evidencia de regla ALB para `/api/catalog/*`.
4. Evidencia de regla ALB para `/api/auth/*`.
5. Evidencia de regla ALB para `/api/profile/*`.
6. Captura o salida de `/api/catalog/products`.
7. Captura o salida de `/api/auth/login`.
8. Captura o salida de `/api/profile/me`.
9. Evidencia de logs o metricas en CloudWatch.
10. Analisis de falla de `auth-service`.

## Rubrica

Total: 100 puntos.

| Criterio | Puntos |
|---|---:|
| Ejercicio 1: separa servicio simple y lo observa | 25 |
| Ejercicio 2: separa login correctamente | 25 |
| Ejercicio 3: demuestra comunicacion entre servicios | 25 |
| Analiza fallas y dependencias | 15 |
| Entregable claro y ordenado | 10 |

## Que faltaria para produccion

- HTTPS end-to-end.
- Autenticacion real con Cognito, OIDC o JWT firmado.
- Secrets fuera del codigo.
- IAM y security groups con minimo privilegio.
- CloudWatch dashboards.
- Alarmas.
- Acciones automatizadas o runbooks ante alarmas.
- Timeouts entre servicios.
- Retries controlados.
- Circuit breaker o fallback.
- Logs sin PII.
- Deploy automatizado.
- Tests de contrato.

## Cierre docente

Frase:

> El primer microservicio puede ser simple. Lo importante es que tenga responsabilidad clara, health check propio, logs propios y un contrato explicito.

Pregunta final:

> Cuando separamos una aplicacion en partes mas chicas, que ganamos y que complejidad nueva aparece?
