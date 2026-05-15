# Matriz 6R - CloudCuyo Migration Strategy

## Arquitectura actual (On-premise)

```
┌─────────────────────────────────────────────────────────────┐
│                      Load Balancer (lb01)                   │
│                     NGINX - 192.168.56.10                   │
└────────┬─────────────────────────────────┬──────────────────┘
         │                                 │
    ┌────▼────────┐                  ┌─────▼─────────┐
    │  Frontend   │                  │  API Backend  │
    │  (NGINX)    │                  │  (Flask)      │
    │  frontend01 │◄─────────────────┤  api01        │
    │  frontend02 │   Llama APIs     │  Port 5000    │
    └─────────────┘   internas       └───────┬───────┘
                      y públicas             │
                                      ┌──────▼────────┐
                                      │  PostgreSQL   │
                                      │  db01         │
                                      │  + pgcrypto   │
                                      └───────────────┘
```

## Funcionalidades clave

### Frontend
- Sitio institucional público (legacy design)
- **Portal de clientes** con login (customer_code + email)
- Dashboard de usuario con:
  - Servicios contratados
  - Historial de pagos
  - Estado de cuenta

### API Backend
**APIs internas (para frontend):**
- `POST /api/auth/login` - Autenticación de clientes
- `GET /api/customers/<code>/services` - Servicios del cliente
- `GET /api/customers/<code>/payments` - Historial de pagos
- `GET /api/health` - Health check interno
- `POST /api/contact` - Formulario de contacto

**APIs públicas v1 (para clientes externos, pasan por LB):**
- `GET /api/v1/customers/<code>/status` - Estado de servicios (monitoreo)
- `GET /api/v1/customers/<code>/billing` - Info de facturación
- `GET /api/v1/health` - Health check público

### Base de datos
- PostgreSQL con extensión `pgcrypto`
- Datos encriptados: tarjetas de crédito, tax IDs
- Tablas: customers, customer_services, payment_history, solutions, contacts
- **Datos históricos críticos** (5-8 años de registros)

## Matriz 6R

| Componente | Estrategia | Justificación | Destino AWS | Complejidad |
|------------|-----------|---------------|-------------|-------------|
| **Load Balancer (NGINX)** | **REPLACE** | Reemplazar por servicio gestionado nativo de AWS | Application Load Balancer (ALB) | Baja |
| **Frontend (sitio + portal)** | **REPLATFORM** | Migrar de NGINX en VM a almacenamiento estático | S3 + CloudFront + Route53 | Media |
| **API Backend (Flask)** | **REFACTOR** | Desacoplar y modernizar a serverless/containers | Lambda + API Gateway o ECS Fargate | Alta |
| **Base de datos (PostgreSQL)** | **REHOST** | Lift & shift temporal por datos encriptados legacy | EC2 + PostgreSQL (bloqueador: pgcrypto) | Media |
| **API pública v1** | **REFACTOR** | Separar APIs públicas del monolito | Lambda + API Gateway | Media |
| **Portal de clientes** | **REPLATFORM** | Modernizar autenticación | S3 + CloudFront + Cognito | Alta |
| **Página promociones 2009** | **RETIRE** | Contenido obsoleto sin tráfico | N/A (eliminar) | Baja |

## Plan de migración por fases

### **Fase 1: Rehost rápido (MVP funcional en AWS)**
**Objetivo:** Migrar infraestructura básica en 2 semanas

```
┌─────────────────────┐
│  Route53            │
│  cloudcuyo.com      │
└──────────┬──────────┘
           │
┌──────────▼──────────┐
│  Application LB     │  ← REPLACE
│  (ALB)              │
└────┬───────────┬────┘
     │           │
┌────▼─────┐  ┌─▼─────────────┐
│ EC2      │  │ EC2            │  ← REHOST
│ NGINX    │  │ Flask API      │
│ Frontend │  │ Gunicorn       │
└──────────┘  └────────┬───────┘
                       │
              ┌────────▼────────┐
              │ EC2 PostgreSQL  │  ← REHOST (temporal)
              │ + pgcrypto      │
              └─────────────────┘
```

**Componentes:**
- **ALB** (REPLACE): Sustituye NGINX lb01
- **EC2 Frontend** (REHOST): t3.micro, Ubuntu + NGINX
- **EC2 API** (REHOST): t3.small, Ubuntu + Python 3.11 + Flask
- **EC2 Database** (REHOST): t3.medium, PostgreSQL 14
  - **Razón del REHOST:** Datos encriptados con `pgcrypto` y clave hardcoded legacy
  - **Bloqueador técnico:** Requiere re-encriptación con AWS KMS antes de migrar a RDS
  - **Plan:** Postponer a Fase 3

**Estrategia de datos:**
- Backup completo de PostgreSQL
- `pg_dump` con datos encriptados intactos
- Restauración en EC2 manteniendo la misma versión de PostgreSQL

---

### **Fase 2: Replatform frontend (modernización)**
**Objetivo:** Optimizar costos y performance del frontend

```
┌─────────────────────┐
│  Route53            │
│  cloudcuyo.com      │
└──────────┬──────────┘
           │
┌──────────▼──────────┐
│  CloudFront (CDN)   │  ← REPLATFORM
│  + S3 bucket        │
│  (sitio estático)   │
└─────────────────────┘
           │
           │ API calls
           ▼
┌─────────────────────┐
│  ALB                │
└────┬────────────────┘
     │
┌────▼─────────────┐
│ EC2 Flask API    │
│ o ECS Fargate    │  ← Comenzar REFACTOR
└────────┬─────────┘
         │
┌────────▼─────────┐
│ EC2 PostgreSQL   │
└──────────────────┘
```

**Componentes:**
- **S3 + CloudFront** (REPLATFORM):
  - `index.html`, `portal.html`, CSS, JS → S3 bucket
  - CloudFront CDN global
  - Certificado SSL/TLS con ACM
- **Autenticación (futuro):**
  - Reemplazar login básico por **AWS Cognito**
  - JWT tokens para APIs
  
**Beneficios:**
- Eliminación de servidor web
- Reducción de costos ~70% en frontend
- Performance global con CDN

---

### **Fase 3: Refactor API + Migración DB**
**Objetivo:** Modernizar backend y resolver bloqueador de base de datos

#### **3A: Resolver bloqueador de base de datos**

**Problema:**
- Datos sensibles encriptados con `pgcrypto` y clave hardcoded: `'cloudcuyo-secret-key-2018'`
- RDS no permite control directo de extensiones legacy
- Necesidad de cumplimiento de seguridad

**Solución:**
1. **Re-encriptación de datos:**
   ```sql
   -- Migración de pgcrypto a AWS KMS
   UPDATE customers SET 
     encrypted_credit_card = encrypt_with_kms(
       pgp_sym_decrypt(encrypted_credit_card, 'cloudcuyo-secret-key-2018')
     ),
     encrypted_tax_id = encrypt_with_kms(
       pgp_sym_decrypt(encrypted_tax_id, 'cloudcuyo-secret-key-2018')
     );
   ```

2. **Migración a RDS:**
   - RDS PostgreSQL con encryption at rest
   - AWS KMS para datos sensibles
   - Secrets Manager para credenciales

#### **3B: Refactor de API**

**Arquitectura objetivo:**

```
┌─────────────────────────────────────────────┐
│  API Gateway (REST)                         │
│  /api/v1/* → APIs públicas                  │
│  /api/* → APIs internas                     │
└─────┬───────────────────────────┬───────────┘
      │                           │
┌─────▼─────────┐       ┌─────────▼─────────┐
│ Lambda        │       │ ECS Fargate       │
│ (APIs livianas│       │ (Flask app)       │
│  públicas)    │       │ o migrar a        │
│               │       │ Lambda container  │
└───────┬───────┘       └─────────┬─────────┘
        │                         │
        └────────┬────────────────┘
                 │
        ┌────────▼─────────┐
        │ RDS PostgreSQL   │  ← REPLATFORM
        │ (Multi-AZ)       │
        │ + KMS encryption │
        └──────────────────┘
```

**Refactor:**
- Separar APIs públicas (`/api/v1/*`) en Lambdas independientes
- APIs internas mantenerlas en contenedor ECS o migrar a Lambda
- API Gateway como único punto de entrada
- Cognito para autenticación
- Secrets Manager para DB credentials

---

### **Fase 4: Retire & Retain**

#### **RETIRE:**
- **Página promociones 2009:** eliminar completamente
- **Código legacy sin uso:** funciones deprecated en API
- **Configuraciones on-premise:** scripts de backup a cinta

#### **RETAIN:**
- **Acceso clientes legacy (tabla: `legacy_pages`):** mantener temporalmente hasta validar migraciones completas
- **Logs históricos:** archivar en S3 Glacier para compliance

---

## Decisiones de arquitectura

### ¿Por qué REHOST en la base de datos?

**Bloqueadores técnicos:**
1. **Encriptación legacy:** uso de `pgcrypto` con clave hardcoded
2. **Volumen de datos:** 5-8 años de historia de pagos y clientes
3. **Compliance:** necesidad de auditoría completa antes de re-encriptar
4. **Dependencias:** la API accede directamente a campos encriptados

**Plan de resolución:**
- Fase 1: REHOST a EC2 para funcionalidad inmediata
- Fase 3: Re-encriptar con KMS y migrar a RDS

### ¿Por qué REFACTOR en el backend?

**Razones:**
1. **APIs públicas:** Los clientes externos dependen de `/api/v1/*`
2. **Escalabilidad:** necesidad de autoscaling independiente
3. **Costos:** pagar solo por uso real (serverless)
4. **Modernización:** desacoplar lógica de negocio

### ¿Por qué REPLACE en el load balancer?

**Beneficios de ALB vs NGINX:**
- Gestionado por AWS (sin mantenimiento)
- Health checks automáticos
- Integración nativa con EC2, ECS, Lambda
- WAF opcional
- Certificados SSL automáticos con ACM

---

## Resumen ejecutivo

| Fase | Duración | Estrategias aplicadas | Resultado |
|------|----------|----------------------|-----------|
| Fase 1 | 2 semanas | REHOST (API, DB) + REPLACE (LB) | Infraestructura funcionando en AWS |
| Fase 2 | 1 semana | REPLATFORM (Frontend) | CDN global, reducción de costos 70% |
| Fase 3 | 3-4 semanas | REFACTOR (API) + REPLATFORM (DB) | Arquitectura serverless, DB gestionada |
| Fase 4 | 1 semana | RETIRE + RETAIN | Limpieza y archivo |

**Total:** 7-8 semanas para migración completa con todas las estrategias 6R demostradas.
