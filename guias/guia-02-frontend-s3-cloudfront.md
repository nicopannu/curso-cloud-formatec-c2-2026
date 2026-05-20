# Guia 2: REPLATFORM Frontend - S3 + CloudFront

**Objetivo:** migrar el frontend estatico de CloudCuyo desde instancias EC2 a S3 + CloudFront, validar la URL CDN y apagar las EC2 de frontend. En una fase posterior se agrega un ALB para exponer la API y apagar `lb01`.

**Duracion estimada:** 2-3 horas

**Estrategia 6R:** **REPLATFORM**

---

## Contexto

Despues del REHOST del Lab 1, CloudCuyo todavia sirve contenido estatico desde instancias EC2. Este lab mueve el sitio estatico a S3 + CloudFront para reducir costo operativo y mejorar disponibilidad/performance.

**Antes:**

- `lb01` publico en EC2.
- `frontend01` y `frontend02` en EC2 sirviendo HTML/CSS/JS.
- `api01` y `db01` siguen en EC2.

**Despues de esta primera validacion:**

- Frontend estatico en bucket S3 privado.
- CloudFront como CDN publico del frontend.
- `frontend01` y `frontend02` apagadas.
- `lb01`, `api01` y `db01` quedan encendidas para la siguiente fase.

**Siguiente fase:**

- Crear Application Load Balancer para `/api/*`.
- Agregar segundo origen en CloudFront apuntando al ALB.
- Validar portal completo por CDN.
- Apagar `lb01`.

---

## Arquitectura objetivo por fases

### Fase A - CDN estatico

```text
Usuario
  |
  v
CloudFront
  |
  v
S3 privado: index.html, portal.html, assets/*
```

En esta fase se valida contenido estatico. Las llamadas `/api/*` todavia no quedan resueltas por CloudFront.

### Fase B - CDN + API por ALB

```text
Usuario
  |
  v
CloudFront
  |-- Default behavior --> S3 privado frontend
  |
  |-- /api/* -----------> ALB publico ---> api01:5000 ---> db01
```

---

## Pre-requisitos

- Lab 1 completado o recursos de REHOST recreados por el instructor.
- VPC del laboratorio identificada.
- `db01`, `api01`, `frontend01`, `frontend02` y `lb01` disponibles inicialmente.
- Acceso a AWS Console.
- Permisos para S3, CloudFront, EC2 y VPC.
- Region del lab: `us-east-1`.

### Pre-requisito para la fase ALB: segunda subnet publica

CloudFront puede crearse con un solo origen S3, pero la fase posterior con Application Load Balancer requiere subnets publicas en al menos dos Availability Zones.

Si la VPC del laboratorio tiene una sola subnet publica, crear una segunda subnet publica antes de construir el ALB:

1. Ir a **VPC > Subnets**.
2. Click en **Create subnet**.
3. Seleccionar la VPC del laboratorio.
4. Crear una subnet con estos criterios:
   - **Subnet name:** `cloudcuyo-public2-us-east-1b`.
   - **Availability Zone:** una AZ distinta a la subnet publica existente, por ejemplo `us-east-1b`.
   - **IPv4 subnet CIDR block:** un rango libre dentro de la VPC, por ejemplo `10.0.2.0/24` si no esta usado.
5. Crear la subnet.
6. Seleccionarla y entrar a **Actions > Edit subnet settings**.
7. Activar **Enable auto-assign public IPv4 address**.
8. Ir a **Route tables**.
9. Seleccionar la route table publica del laboratorio, la que tiene ruta `0.0.0.0/0` hacia el Internet Gateway.
10. En **Subnet associations**, asociar la nueva subnet publica.

> Esta subnet se documenta ahora para no bloquear la fase ALB. No es necesaria para crear el bucket S3 ni la primera distribucion CloudFront estatica.

---

## Fase 1: Validar estado inicial del REHOST

1. Ir a **EC2 > Instances**.
2. Confirmar que existan y esten `Running`:
   - `cloudcuyo-db01` o `cloudcuyo-demo-db01`.
   - `cloudcuyo-api01` o `cloudcuyo-demo-api01`.
   - `cloudcuyo-frontend01` o `cloudcuyo-demo-frontend01`.
   - `cloudcuyo-frontend02` o `cloudcuyo-demo-frontend02`.
   - `cloudcuyo-lb01` o `cloudcuyo-demo-lb01`.
3. Copiar la IP publica de `lb01`.
4. Abrir en el navegador:
   - `http://<ip-publica-lb01>/`
   - `http://<ip-publica-lb01>/portal.html`
   - `http://<ip-publica-lb01>/api/health`
5. Si falla esta validacion, resolver el REHOST antes de continuar con S3/CloudFront.

---

## Fase 2: Crear bucket S3 privado

1. Ir a **S3**.
2. Click en **Create bucket**.
3. Configurar:
   - **Bucket name:** `cloudcuyo-frontend-<identificador-unico>`.
   - **AWS Region:** `us-east-1`.
   - **Object Ownership:** dejar valor por defecto recomendado.
   - **Block Public Access settings:** dejar todo marcado.
   - **Bucket Versioning:** `Enable`.
   - Resto de opciones: dejar por defecto.
4. Click en **Create bucket**.
5. Anotar el nombre exacto del bucket.

> El bucket debe permanecer privado. CloudFront accedera usando Origin Access Control (OAC).

---

## Fase 3: Subir archivos del frontend

1. Entrar al bucket creado.
2. Click en **Upload**.
3. Desde el repositorio local, abrir `app/frontend/`.
4. Subir solo los archivos del sitio:
   - `index.html`
   - `portal.html`
   - `clientes.html`
   - `contacto.html`
   - `hosting.html`
   - `soluciones.html`
   - carpeta `assets/` completa
5. No subir `.git`, documentacion, scripts ni carpetas de desarrollo.
6. Click en **Upload** y esperar a que finalice.
7. Verificar que en el bucket se vean los HTML en la raiz y `assets/css/` y `assets/js/` como carpetas.

### Verificar metadata si algo carga mal

S3 normalmente detecta el `Content-Type`. Si el navegador descarga archivos en vez de renderizarlos:

1. Seleccionar el objeto afectado.
2. Ir a **Properties > Metadata**.
3. Confirmar valores esperados:
   - `.html`: `text/html`
   - `.css`: `text/css`
   - `.js`: `application/javascript`

---

## Fase 4: Crear CloudFront con origen S3

### 4.1 Crear Origin Access Control

1. Ir a **CloudFront**.
2. En el menu lateral, entrar a **Origin access**.
3. Abrir la pestana **Origin access control**.
4. Click en **Create control setting**.
5. Configurar:
   - **Name:** `cloudcuyo-oac`.
   - **Description:** `CloudCuyo S3 Origin Access Control`.
   - **Origin type:** `S3`.
   - **Signing behavior:** `Sign requests`.
   - **Signing protocol:** `SigV4`.
6. Click en **Create**.

### 4.2 Crear distribucion CloudFront

1. Ir a **CloudFront > Distributions**.
2. Click en **Create distribution**.
3. En **Origin domain**, seleccionar el bucket S3 creado.
4. En **Origin access**, elegir **Origin access control settings (recommended)**.
5. En **Origin access control**, seleccionar `cloudcuyo-oac`.
6. En **Default cache behavior** configurar:
   - **Viewer protocol policy:** `Redirect HTTP to HTTPS`.
   - **Allowed HTTP methods:** `GET, HEAD`.
   - **Compress objects automatically:** `Yes`.
7. En **Settings** configurar:
   - **Price class:** `Use only North America and Europe`.
   - **Default root object:** `index.html`.
8. Click en **Create distribution**.
9. Anotar:
   - **Distribution ID**.
   - **Distribution domain name**, por ejemplo `dxxxxxxxxxxxxx.cloudfront.net`.

### 4.3 Actualizar bucket policy para OAC

Despues de crear la distribucion, CloudFront muestra un aviso indicando que la bucket policy debe actualizarse.

1. En el aviso de CloudFront, click en **Copy policy**.
2. Ir a **S3 > bucket del frontend > Permissions**.
3. En **Bucket policy**, click en **Edit**.
4. Pegar la politica generada por CloudFront.
5. Verificar que la politica:
   - Permite `s3:GetObject`.
   - Usa principal `cloudfront.amazonaws.com`.
   - Limita acceso con `AWS:SourceArn` a la distribucion creada.
6. Click en **Save changes**.

---

## Fase 5: Esperar despliegue y validar CDN estatico

1. Volver a **CloudFront > Distributions**.
2. Esperar a que el estado de la distribucion pase de `Deploying` a `Enabled` / `Deployed`.
3. Abrir en el navegador:
   - `https://<distribution-domain>/`
   - `https://<distribution-domain>/portal.html`
   - `https://<distribution-domain>/clientes.html`
   - `https://<distribution-domain>/hosting.html`
   - `https://<distribution-domain>/contacto.html`
4. Confirmar que cargan estilos e interacciones basicas.

### Resultado esperado en esta fase

- El contenido estatico carga desde CloudFront.
- El bucket S3 no es publico.
- Las rutas `/api/*` todavia pueden fallar desde CloudFront. Esto es esperado hasta configurar el ALB en la fase posterior.

### Problemas frecuentes

| Sintoma | Posible causa | Correccion |
|---|---|---|
| `403 AccessDenied` | Bucket policy OAC faltante o incorrecta | Copiar nuevamente la policy generada por CloudFront |
| `404 Not Found` en `/` | Falta default root object | Configurar `index.html` |
| HTML sin estilos | No se subio `assets/` o Content-Type incorrecto | Revisar objetos y metadata |
| Cambios no aparecen | Cache de CloudFront | Crear invalidation para los paths modificados |
| Login/API falla | Falta configurar ALB y behavior `/api/*` | Continuar con fase posterior |

---

## Fase 6: Apagar EC2 de frontend

Cuando el sitio estatico ya carga correctamente desde CloudFront:

1. Ir a **EC2 > Instances**.
2. Seleccionar:
   - `cloudcuyo-frontend01` o `cloudcuyo-demo-frontend01`.
   - `cloudcuyo-frontend02` o `cloudcuyo-demo-frontend02`.
3. Click en **Instance state > Stop instance**.
4. Confirmar.
5. Validar nuevamente la URL de CloudFront.

> En esta etapa no apagar `lb01`, `api01` ni `db01`. Se necesitan para la fase ALB/API.

---

## Fase 7: Crear ALB para la API

Esta fase permite que el portal servido por CloudFront use la API sin depender de `lb01`.

Arquitectura de esta fase:

```text
CloudFront
  |-- default  --> S3 frontend
  |-- /api/*   --> ALB publico --> api01:5000 --> db01:5432
```

### 7.1 Confirmar prerequisitos

1. Ir a **EC2 > Instances**.
2. Confirmar que `api01` este `Running`.
3. Confirmar que `db01` este `Running`.
4. Confirmar que `frontend01` y `frontend02` pueden seguir apagadas.
5. Ir a **VPC > Subnets** y confirmar que existan dos subnets publicas en AZs distintas.
6. Confirmar que ambas subnets publicas esten asociadas a una route table con ruta `0.0.0.0/0` hacia el Internet Gateway.

### 7.2 Crear Security Group para el ALB

1. Ir a **EC2 > Security Groups**.
2. Click en **Create security group**.
3. Configurar:
   - **Security group name:** `cloudcuyo-alb-api-sg`.
   - **Description:** `CloudCuyo API ALB public access`.
   - **VPC:** VPC del laboratorio.
4. En **Inbound rules**, agregar:
   - **Type:** `HTTP`.
   - **Protocol:** `TCP`.
   - **Port:** `80`.
   - **Source:** `0.0.0.0/0`.
5. En **Outbound rules**, dejar **All traffic**.
6. Crear el Security Group.

### 7.3 Permitir que el ALB llegue a `api01`

1. Ir a **EC2 > Security Groups**.
2. Seleccionar el Security Group usado por `api01`.
3. Entrar a **Inbound rules > Edit inbound rules**.
4. Agregar regla:
   - **Type:** `Custom TCP`.
   - **Port range:** `5000`.
   - **Source:** seleccionar el Security Group `cloudcuyo-alb-api-sg`.
5. Guardar cambios.

> No abrir `api01:5000` a `0.0.0.0/0`. Solo debe aceptar trafico desde el Security Group del ALB.

### 7.4 Crear Target Group para `api01`

1. Ir a **EC2 > Target Groups**.
2. Click en **Create target group**.
3. Configurar:
   - **Choose a target type:** `Instances`.
   - **Target group name:** `cloudcuyo-api-tg`.
   - **Protocol:** `HTTP`.
   - **Port:** `5000`.
   - **VPC:** VPC del laboratorio.
   - **Protocol version:** `HTTP1`.
4. En **Health checks** configurar:
   - **Health check protocol:** `HTTP`.
   - **Health check path:** `/api/health`.
5. Click en **Next**.
6. Seleccionar la instancia `api01`.
7. Mantener puerto `5000`.
8. Click en **Include as pending below**.
9. Click en **Create target group**.
10. Esperar a que el target quede `Healthy`.

### 7.5 Crear Application Load Balancer

1. Ir a **EC2 > Load Balancers**.
2. Click en **Create load balancer**.
3. Elegir **Application Load Balancer**.
4. Configurar:
   - **Load balancer name:** `cloudcuyo-api-alb`.
   - **Scheme:** `Internet-facing`.
   - **IP address type:** `IPv4`.
5. En **Network mapping**:
   - Seleccionar la VPC del laboratorio.
   - Seleccionar las dos subnets publicas en AZs distintas.
6. En **Security groups**, seleccionar `cloudcuyo-alb-api-sg`.
7. En **Listeners and routing**:
   - **Protocol:** `HTTP`.
   - **Port:** `80`.
   - **Default action:** forward al Target Group `cloudcuyo-api-tg`.
8. Crear el ALB.
9. Copiar el **DNS name** del ALB.
10. Abrir en navegador:
    - `http://<dns-del-alb>/api/health`
11. Confirmar respuesta de la API con `database: ok`.

---

## Fase 8: Conectar CloudFront con el ALB para `/api/*`

### 8.1 Agregar el ALB como origin

1. Ir a **CloudFront > Distributions**.
2. Seleccionar la distribucion creada para el frontend.
3. Entrar a la pestana **Origins**.
4. Click en **Create origin**.
5. Configurar:
   - **Origin domain:** DNS name del ALB `cloudcuyo-api-alb`.
   - **Protocol:** `HTTP only`.
   - **HTTP port:** `80`.
   - **Origin path:** dejar vacio.
   - **Name:** `ALB-API-Backend`.
6. Click en **Create origin**.

### 8.2 Crear behavior para `/api/*`

1. En la misma distribucion, ir a **Behaviors**.
2. Click en **Create behavior**.
3. Configurar:
   - **Path pattern:** `/api/*`.
   - **Origin and origin groups:** `ALB-API-Backend`.
   - **Viewer protocol policy:** `Redirect HTTP to HTTPS`.
   - **Allowed HTTP methods:** `GET, HEAD, OPTIONS, PUT, POST, PATCH, DELETE`.
   - **Cache HTTP methods:** `GET, HEAD`.
   - **Cache policy:** `CachingDisabled`.
   - **Origin request policy:** `AllViewer`.
4. Crear el behavior.
5. Esperar a que la distribucion vuelva a quedar desplegada.

### 8.3 Validar API por CloudFront

1. Abrir en navegador:
   - `https://<distribution-domain>/api/health`
2. Confirmar que responde la API.
3. La respuesta esperada debe indicar que la base esta `ok`.

### 8.4 Validar login completo del portal

1. Abrir:
   - `https://<distribution-domain>/portal.html`
2. Usar las credenciales de prueba:
   - **Codigo:** `CUST-2020-003`
   - **Email:** `lfernandez@techmza.com`
3. Confirmar que el dashboard carga datos del cliente.
4. Confirmar que se cargan servicios y pagos.

### Problemas frecuentes de la fase ALB/API

| Sintoma | Posible causa | Correccion |
|---|---|---|
| Target `api01` queda `Unhealthy` | SG de `api01` no permite puerto `5000` desde el SG del ALB | Revisar regla inbound de `api01` |
| `502 Bad Gateway` desde CloudFront | ALB no llega a la API o target unhealthy | Revisar Target Group y health check |
| `/api/health` responde pero login falla | Metodo POST o headers no reenviados | Revisar behavior `/api/*`, metodos permitidos y Origin request policy `AllViewer` |
| API responde error de DB | PostgreSQL no permite la red VPC o DB caida | Revisar `pg_hba.conf`, servicio PostgreSQL y SG de DB |
| CloudFront sigue fallando tras corregir | Distribucion aun desplegando o cache | Esperar despliegue o invalidar `/api/*` |

---

## Fase 9: Apagar `lb01`

Cuando el portal completo funciona por CloudFront:

1. Ir a **EC2 > Instances**.
2. Seleccionar `cloudcuyo-lb01` o `cloudcuyo-demo-lb01`.
3. Click en **Instance state > Stop instance**.
4. Confirmar.
5. Volver a probar:
   - `https://<distribution-domain>/`
   - `https://<distribution-domain>/portal.html`
   - Login del portal.

> Despues de esta fase, el frontend estatico depende de S3 + CloudFront y la API se publica por ALB. `lb01`, `frontend01` y `frontend02` ya no son necesarios para atender usuarios.

---

## Limpieza

Si se desea eliminar lo creado en este lab:

1. En **CloudFront**, deshabilitar la distribucion.
2. Esperar a que quede deshabilitada.
3. Eliminar la distribucion.
4. En **S3**, vaciar el bucket del frontend.
5. Eliminar el bucket.
6. Si se creo una segunda subnet publica solo para pruebas y no se usara para ALB, desasociarla de recursos y eliminarla.

---

## Criterios de exito

- CloudFront entrega el frontend estatico desde una URL `https://dxxxx.cloudfront.net`.
- El bucket S3 permanece privado.
- `frontend01` y `frontend02` pueden quedar apagadas sin afectar la carga estatica del sitio.
- El behavior `/api/*` de CloudFront llega al ALB y a `api01`.
- El login del portal funciona desde la URL CDN.
- `lb01` puede quedar apagado sin afectar el sitio ni la API publicada por CloudFront.
