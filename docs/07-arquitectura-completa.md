# Arquitectura completa CloudCuyo

## Descripción general

CloudCuyo es una empresa legacy de hosting y servicios cloud que opera desde 2001 con una arquitectura on-premise tradicional. La empresa ofrece:

- Portal web institucional
- Portal de clientes con autenticación
- APIs públicas para integraciones de clientes
- Base de datos con información histórica y datos sensibles encriptados

## Componentes on-premise (actuales)

### 1. Load Balancer (lb01)
- **Servicio:** NGINX
- **IP:** 192.168.56.10
- **Función:** 
  - Distribuir tráfico entre servidores frontend (round-robin)
  - Proxy reverso para API backend
  - Punto de entrada único para todo el tráfico

**Configuración:**
```nginx
upstream cloudcuyo_frontend {
    server 192.168.56.20:80;  # frontend01
    server 192.168.56.21:80;  # frontend02
}

upstream cloudcuyo_api {
    server 192.168.56.30:5000;  # api01
}

location /api/ {
    proxy_pass http://cloudcuyo_api/api/;
}

location / {
    proxy_pass http://cloudcuyo_frontend;
}
```

### 2. Frontend (frontend01, frontend02)
- **Servicio:** NGINX sirviendo contenido estático
- **IPs:** 192.168.56.20, 192.168.56.21
- **Alta disponibilidad:** 2 instancias detrás del LB

**Páginas:**
- `index.html` - Home institucional (legacy design)
- `portal.html` - Portal de clientes con login
- `soluciones.html` - Catálogo de servicios
- `clientes.html` - Testimonios
- `contacto.html` - Formulario de contacto
- `hosting.html` - Info de planes

**Portal de clientes:**
- Login con `customer_code` + `email`
- Dashboard con servicios contratados
- Historial de pagos (últimos 10)
- Estado de cuenta en tiempo real

### 3. API Backend (api01)
- **Framework:** Flask (Python 3.11)
- **IP:** 192.168.56.30:5000
- **Servidor:** Gunicorn

#### **APIs internas (para frontend):**

| Endpoint | Método | Descripción |
|----------|--------|-------------|
| `/api/health` | GET | Health check con estado de DB |
| `/api/auth/login` | POST | Autenticación de clientes |
| `/api/solutions` | GET | Listado de servicios ofrecidos |
| `/api/contact` | POST | Formulario de contacto |
| `/api/customers` | GET | Listado de clientes activos |
| `/api/customers/<code>/services` | GET | Servicios contratados por cliente |
| `/api/customers/<code>/payments` | GET | Historial de pagos del cliente |
| `/api/messages` | GET | Mensajes de contacto recibidos |
| `/api/stats` | GET | Estadísticas generales del sistema |

#### **APIs públicas v1 (para clientes externos):**

Estas APIs están diseñadas para que los clientes de CloudCuyo integren con sus sistemas de monitoreo y facturación:

| Endpoint | Método | Descripción | Uso |
|----------|--------|-------------|-----|
| `/api/v1/health` | GET | Health check público | Monitoreo externo |
| `/api/v1/customers/<code>/status` | GET | Estado de servicios contratados | Dashboards de clientes |
| `/api/v1/customers/<code>/billing` | GET | Info de facturación resumida | Sistemas contables |

**Ejemplo de uso:**
```bash
# Cliente externo consulta estado de sus servicios
curl http://cloudcuyo.com/api/v1/customers/CUST-2020-003/status

# Respuesta:
{
  "customer_code": "CUST-2020-003",
  "company_name": "Consultora TechMza",
  "status": "active",
  "services": [
    {
      "name": "Servidores administrados",
      "status": "active",
      "monthly_cost": 35000.00
    },
    {
      "name": "Consultoria cloud",
      "status": "active",
      "monthly_cost": 25000.00
    }
  ],
  "api_version": "v1"
}
```

**Características técnicas:**
- CORS habilitado para frontend
- Conexión directa a PostgreSQL con `psycopg2`
- Variables de entorno para configuración de DB
- Sin autenticación en APIs públicas (solo validación de customer_code)

### 4. Base de datos (db01)
- **Motor:** PostgreSQL 14
- **IP:** 192.168.56.40:5432
- **Base de datos:** `cloudcuyo`
- **Usuario:** `cloudcuyo` / `cloudcuyo`

#### **Esquema de datos:**

**Tabla: `customers`**
```sql
- id (serial PK)
- customer_code (text UNIQUE)  -- ej: CUST-2020-003
- company_name
- contact_name
- email
- phone
- encrypted_credit_card (bytea)  -- ⚠️ pgcrypto
- encrypted_tax_id (bytea)       -- ⚠️ pgcrypto
- contract_start_date
- contract_end_date
- total_spent (numeric)
- is_active (boolean)
```

**Tabla: `customer_services`**
```sql
- id (serial PK)
- customer_id (FK → customers)
- solution_id (FK → solutions)
- contracted_date
- monthly_cost (numeric)
- status (active/suspended/cancelled)
```

**Tabla: `payment_history`**
```sql
- id (serial PK)
- customer_id (FK → customers)
- amount (numeric)
- payment_date
- payment_method
- transaction_id (unique)
- status (completed/pending/failed/refunded)
- notes
```

**Tabla: `solutions`**
```sql
- id (serial PK)
- name
- description
- strategy_hint  -- Para matriz 6R
```

**Tabla: `contacts`**
```sql
- id (serial PK)
- name
- email
- category
- message
- created_at
```

**Tabla: `legacy_pages`**
```sql
- id (serial PK)
- slug
- title
- active (boolean)
- migration_strategy  -- Para framework 6R
```

#### **⚠️ Datos encriptados (bloqueador de migración):**

CloudCuyo utiliza la extensión `pgcrypto` de PostgreSQL con una clave hardcoded para encriptar datos sensibles:

```sql
-- Encriptación (usado en seed.sql)
pgp_sym_encrypt('4532-1234-5678-9010', 'cloudcuyo-secret-key-2018')

-- Desencriptación (usado en API)
pgp_sym_decrypt(encrypted_credit_card, 'cloudcuyo-secret-key-2018')
```

**Problemas para migración:**
1. Clave hardcoded en código y scripts
2. RDS no soporta control directo de `pgcrypto` legacy
3. Necesidad de re-encriptación para cumplimiento (AWS KMS)
4. Alto riesgo en migración de datos sensibles

**Solución propuesta:** REHOST temporal a EC2, re-encriptar en Fase 3, migrar a RDS con KMS.

#### **Datos de ejemplo:**

La base de datos contiene:
- 6 clientes (5 activos, 1 inactivo)
- 4 soluciones/servicios
- 12 servicios contratados
- 11 pagos históricos

Clientes ejemplo:
- `CUST-2018-001` - Bodegas del Valle SA
- `CUST-2019-002` - Viñedos Andinos SRL
- `CUST-2020-003` - Consultora TechMza
- `CUST-2021-005` - Inmobiliaria Cuyo Real

---

## Flujo de datos

### 1. Usuario accede al sitio público
```
Usuario → http://192.168.56.10
  → lb01 (NGINX)
    → frontend01 o frontend02 (round-robin)
      → Sirve index.html + assets
```

### 2. Usuario consulta estado de servicios (frontend)
```
Browser → GET /api/health
  → lb01 proxy
    → api01 Flask
      → query PostgreSQL db01
        → Respuesta JSON
```

### 3. Cliente inicia sesión en portal
```
Browser → POST /api/auth/login
  Body: {"customer_code": "CUST-2020-003", "email": "..."}
  → lb01 proxy
    → api01 Flask
      → query customers WHERE customer_code=X AND email=Y
        → Si válido: retorna datos de cliente
          → Browser almacena en sessionStorage
            → Carga dashboard con servicios y pagos
```

### 4. Cliente externo consulta API pública
```
Sistema del cliente → GET /api/v1/customers/CUST-2020-003/status
  → lb01 proxy
    → api01 Flask
      → query customer_services JOIN solutions
        → Respuesta JSON con servicios activos
          → Sistema del cliente procesa respuesta
```

---

## Razones para demostrar 6R

### 1. REHOST (Base de datos)
**Razón:** Datos encriptados legacy que requieren análisis antes de modernizar
- Bloqueador técnico: pgcrypto con clave hardcoded
- Datos históricos críticos (5-8 años)
- Necesidad de compliance antes de re-encriptar

**Estrategia:** Lift & shift a EC2 + PostgreSQL, postponer RDS a Fase 3

### 2. REPLATFORM (Frontend)
**Razón:** Contenido estático sin lógica de servidor
- Fácil migración a S3 + CloudFront
- Reducción de costos ~70%
- Mejora de performance con CDN global

**Estrategia:** Migrar HTML/CSS/JS a S3, configurar CloudFront

### 3. REFACTOR (API Backend)
**Razón:** Separar APIs públicas del monolito
- Escalabilidad independiente
- Costos optimizados (serverless)
- Modernización de arquitectura

**Estrategia:** Lambda + API Gateway para APIs públicas, ECS/Fargate para monolito

### 4. REPLACE (Load Balancer)
**Razón:** NGINX requiere mantenimiento manual
- ALB es gestionado por AWS
- Integración nativa con servicios AWS
- Health checks automáticos

**Estrategia:** Reemplazar por Application Load Balancer

### 5. RETIRE (Página promociones 2009)
**Razón:** Contenido obsoleto sin tráfico
- Sin valor operativo
- Confusión para usuarios

**Estrategia:** Eliminar completamente

### 6. RETAIN (Acceso clientes legacy)
**Razón:** Dependencias desconocidas, mantener hasta validar
- Tabla `legacy_pages` con slug `clientes-legacy`
- Análisis de tráfico necesario antes de eliminar

**Estrategia:** Mantener temporalmente, monitorear uso

---

## Cómo ejecutar localmente (Vagrant)

### Requisitos previos
- VirtualBox instalado
- Vagrant instalado
- 4 GB RAM disponibles
- 10 GB espacio en disco

### Levantar todas las VMs
```bash
cd C:\Users\Nico\github-curso\curso-cloud-formatec-c2-2026
vagrant up
```

Esto levanta en orden:
1. `db01` - PostgreSQL (192.168.56.40)
2. `api01` - Flask API (192.168.56.30:5000)
3. `frontend01` - NGINX (192.168.56.20)
4. `frontend02` - NGINX (192.168.56.21)
5. `lb01` - Load Balancer (192.168.56.10)

### Acceso a servicios
- **Sitio principal:** http://192.168.56.10
- **Portal de clientes:** http://192.168.56.10/portal.html
- **API directa:** http://192.168.56.30:5000/api/health
- **API a través del LB:** http://192.168.56.10/api/health

### Probar API pública
```bash
# Health check
curl http://192.168.56.10/api/v1/health

# Estado de servicios de un cliente
curl http://192.168.56.10/api/v1/customers/CUST-2020-003/status

# Facturación de un cliente
curl http://192.168.56.10/api/v1/customers/CUST-2020-003/billing
```

### Probar portal de clientes
1. Abrir http://192.168.56.10/portal.html
2. Usar credenciales ejemplo:
   - Código: `CUST-2020-003`
   - Email: `lfernandez@techmza.com`
3. Explorar dashboard con servicios y pagos

### Conectar a la base de datos
```bash
vagrant ssh db01
sudo -u postgres psql -d cloudcuyo

# Ver clientes
SELECT customer_code, company_name, email FROM customers WHERE is_active = true;

# Ver servicios de un cliente
SELECT s.name, cs.monthly_cost, cs.status
FROM customer_services cs
JOIN solutions s ON cs.solution_id = s.id
WHERE cs.customer_id = 3;
```

### Detener y limpiar
```bash
# Detener todas las VMs
vagrant halt

# Destruir todas las VMs
vagrant destroy -f
```

---
