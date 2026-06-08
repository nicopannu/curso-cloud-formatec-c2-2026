# Guia Microservicios 01: Descomposición del Buzón CloudCuyo

**Objetivo:** Identificar el límite del servicio "Buzón de contacto", definir su API REST, proponer datos propios y dibujar el flujo principal para separarlo como microservicio independiente.

**Duración estimada:** 2-3 horas (actividad grupal + presentación)

**Estrategia 6R:** **REFACTOR** (preparación para separar como microservicio)

---

## Contexto

CloudCuyo ha migrado exitosamente su infraestructura a AWS y ha implementado alta disponibilidad con ALB y Auto Scaling. Ahora el equipo técnico identifica que el **Buzón de contacto** es un candidato ideal para separarse como microservicio independiente porque:

1. **Bounded Context claro:** Gestionar mensajes de contacto es un dominio funcional bien delimitado
2. **Bajo acoplamiento:** No depende fuertemente de otras funcionalidades del portal
3. **Equipo propietario:** El equipo de atención al cliente tiene ownership funcional
4. **Escalabilidad independiente:** Los picos de mensajes no deberían afectar el resto del portal
5. **Evolución serverless:** Es un buen candidato para convertirse en Lambda + API Gateway en el futuro

**Situación actual (Monolito):**

```
Portal CloudCuyo (EC2)
├── Páginas HTML estáticas
├── Portal de clientes
├── Módulo Soluciones
├── Módulo Clientes
└── Módulo Buzón ← Acoplado al portal
    ├── Formulario contacto.html
    ├── POST /api/contact
    └── GET /api/messages
    
↓ Acceso directo a DB compartida
PostgreSQL (db01)
├── customers
├── solutions
├── customer_services
├── payments
└── messages ← Tabla de buzón mezclada con todo
```

**Arquitectura objetivo (Microservicio):**

```
                    Usuario
                      |
                      v
                 CloudFront
                      |
        ┌─────────────┴─────────────┐
        v                           v
    Portal Web                  API Buzón
   (S3 / ALB)              (API Gateway + Lambda)
        |                           |
        |                           v
        |                      DynamoDB
        |                    (mensajes)
        |                           |
        └───────────[Evento]────────┘
                      |
                      v
              Servicio Notificaciones
                   (SNS/SES)
```

---

## Mensaje central de la clase

> **"Primero límites claros, después servicios."**

Antes de escribir una sola línea de código, necesitamos:
1. Identificar el **Bounded Context** correcto
2. Definir el **contrato de la API** (qué promete, qué recibe, qué devuelve, qué falla)
3. Decidir qué **datos son propios del servicio**
4. Diseñar el **flujo principal** y los modos de falla

---

## Fase 1: Identificar el límite del Bounded Context

### 🎯 Actividad grupal (20 minutos)

Responder estas cinco preguntas clave para validar si el Buzón es un buen candidato a microservicio:

#### 1. ¿Qué cambia junto?

Analizar qué módulos del portal suelen cambiar en conjunto:

- Cuando se modifica el Buzón (agregar campo, cambiar validación, nuevo tipo de mensaje), ¿se modifica el Portal de Clientes?
- Cuando se modifica el Catálogo de Soluciones, ¿se modifica el Buzón?
- ¿El Buzón tiene ciclos de cambio independientes?

**💡 Señal positiva para separación:** El Buzón cambia independientemente del resto del portal.

#### 2. ¿Quién es dueño del dominio?

Identificar ownership funcional:

- ¿Qué equipo de negocio es responsable del Buzón? (Ej: Atención al Cliente)
- ¿Qué equipo de negocio es responsable del Portal de Clientes? (Ej: Producto/Ventas)
- ¿Son equipos diferentes con objetivos diferentes?

**💡 Señal positiva:** Equipos diferentes → microservicios diferentes.

#### 3. ¿Qué datos controla?

Analizar dependencias de datos:

- ¿Qué datos son **exclusivos** del Buzón? (mensajes de contacto)
- ¿Qué datos son **compartidos** con otros módulos? (clientes, soluciones)
- ¿Los mensajes necesitan JOINs complejos con otras tablas?

**💡 Señal positiva:** Los mensajes de contacto tienen pocos JOINs críticos.

#### 4. ¿Qué contrato expone?

Definir las operaciones que el Buzón debe ofrecer:

- Enviar mensaje de contacto
- Listar mensajes (admin)
- Obtener mensaje específico
- Marcar mensaje como leído/respondido

**💡 Señal positiva:** API simple y estable.

#### 5. ¿Cómo falla sin tirar todo?

Analizar modos de falla:

- Si el Buzón está caído, ¿el resto del portal sigue funcionando?
- Si hay pico de mensajes, ¿el portal se degrada?
- ¿Se puede implementar un Circuit Breaker o fallback?

**💡 Señal positiva:** El portal puede funcionar aunque el Buzón falle temporalmente.

---

### 📝 Entregable Fase 1

Crear documento `entregables/01-bounded-context.md` con:

```markdown
# Bounded Context: Buzón de Contacto

## 1. ¿Qué cambia junto?
[Respuesta del grupo]

## 2. ¿Quién es dueño?
[Respuesta del grupo]

## 3. ¿Qué datos controla?
[Respuesta del grupo]

## 4. ¿Qué contrato expone?
[Respuesta del grupo]

## 5. ¿Cómo falla sin tirar todo?
[Respuesta del grupo]

## Conclusión
¿Es el Buzón un buen candidato a microservicio? ¿Por qué?
```

---

## Fase 2: Definir el contrato de la API

### 🎯 Actividad grupal (30 minutos)

Diseñar la API REST del servicio Buzón siguiendo principios de diseño de APIs:

#### Principios de diseño

1. **Recursos, no acciones:** `/mensajes` en lugar de `/enviarMensaje`
2. **Métodos HTTP semánticos:** POST para crear, GET para leer, PUT/PATCH para actualizar
3. **Versionado explícito:** `/v1/mensajes`
4. **Respuestas consistentes:** Siempre incluir `status`, `data`, `error`
5. **Errores explícitos:** Códigos HTTP + mensajes descriptivos
6. **Idempotencia:** POST no idempotente, PUT idempotente
7. **Paginación:** Para listados grandes

#### API propuesta

**Base URL:** `https://api.cloudcuyo.com/buzon/v1`

---

#### **POST /v1/mensajes** - Enviar mensaje de contacto

**Request:**
```json
POST /v1/mensajes
Content-Type: application/json

{
  "nombre": "Juan Pérez",
  "email": "juan@example.com",
  "telefono": "+54 261 123 4567",  // opcional
  "empresa": "Acme Corp",          // opcional
  "asunto": "Consulta sobre hosting",
  "mensaje": "Necesito información sobre planes de hosting...",
  "origen": "web"                   // web | mobile | api
}
```

**Response exitoso (201 Created):**
```json
{
  "status": "success",
  "data": {
    "mensaje_id": "MSG-2026-06-001234",
    "fecha_recepcion": "2026-06-07T19:45:00Z",
    "estado": "pendiente"
  }
}
```

**Response con error (400 Bad Request):**
```json
{
  "status": "error",
  "error": {
    "code": "INVALID_EMAIL",
    "message": "El formato del email es inválido",
    "field": "email"
  }
}
```

**Response con error del servicio (500 Internal Server Error):**
```json
{
  "status": "error",
  "error": {
    "code": "DATABASE_ERROR",
    "message": "Error temporal del servicio. Reintente en unos minutos.",
    "request_id": "req-abc123"
  }
}
```

---

#### **GET /v1/mensajes** - Listar mensajes (admin)

**Request:**
```http
GET /v1/mensajes?estado=pendiente&limit=20&offset=0
Authorization: Bearer <token>
```

**Query parameters:**
- `estado`: `pendiente` | `en_proceso` | `respondido` | `archivado` (opcional)
- `fecha_desde`: ISO 8601 date (opcional)
- `fecha_hasta`: ISO 8601 date (opcional)
- `limit`: número de resultados por página (default: 20, max: 100)
- `offset`: offset para paginación (default: 0)

**Response (200 OK):**
```json
{
  "status": "success",
  "data": {
    "mensajes": [
      {
        "mensaje_id": "MSG-2026-06-001234",
        "nombre": "Juan Pérez",
        "email": "juan@example.com",
        "asunto": "Consulta sobre hosting",
        "estado": "pendiente",
        "fecha_recepcion": "2026-06-07T19:45:00Z"
      },
      // ... más mensajes
    ],
    "pagination": {
      "total": 150,
      "limit": 20,
      "offset": 0,
      "has_more": true
    }
  }
}
```

---

#### **GET /v1/mensajes/{id}** - Obtener mensaje específico

**Request:**
```http
GET /v1/mensajes/MSG-2026-06-001234
Authorization: Bearer <token>
```

**Response (200 OK):**
```json
{
  "status": "success",
  "data": {
    "mensaje_id": "MSG-2026-06-001234",
    "nombre": "Juan Pérez",
    "email": "juan@example.com",
    "telefono": "+54 261 123 4567",
    "empresa": "Acme Corp",
    "asunto": "Consulta sobre hosting",
    "mensaje": "Necesito información sobre planes de hosting...",
    "estado": "pendiente",
    "origen": "web",
    "fecha_recepcion": "2026-06-07T19:45:00Z",
    "fecha_respuesta": null,
    "respondido_por": null,
    "notas_internas": null
  }
}
```

**Response mensaje no encontrado (404 Not Found):**
```json
{
  "status": "error",
  "error": {
    "code": "MESSAGE_NOT_FOUND",
    "message": "El mensaje solicitado no existe"
  }
}
```

---

#### **PATCH /v1/mensajes/{id}/estado** - Actualizar estado del mensaje

**Request:**
```json
PATCH /v1/mensajes/MSG-2026-06-001234/estado
Authorization: Bearer <token>
Content-Type: application/json

{
  "estado": "en_proceso",
  "notas_internas": "Derivado al equipo de ventas"
}
```

**Response (200 OK):**
```json
{
  "status": "success",
  "data": {
    "mensaje_id": "MSG-2026-06-001234",
    "estado": "en_proceso",
    "fecha_actualizacion": "2026-06-07T20:15:00Z"
  }
}
```

---

### Códigos HTTP a usar

| Código | Uso |
|--------|-----|
| 200 OK | Operación exitosa (GET, PATCH) |
| 201 Created | Recurso creado exitosamente (POST) |
| 400 Bad Request | Error de validación en request |
| 401 Unauthorized | Falta autenticación |
| 403 Forbidden | Usuario autenticado pero sin permisos |
| 404 Not Found | Recurso no encontrado |
| 429 Too Many Requests | Rate limit excedido |
| 500 Internal Server Error | Error del servidor |
| 503 Service Unavailable | Servicio temporalmente no disponible |

---

### Timeouts y Circuit Breaker

**Configuración recomendada:**

```yaml
timeout:
  connection: 3s
  request: 10s
  
circuit_breaker:
  failure_threshold: 5      # Abrir circuito tras 5 fallos consecutivos
  success_threshold: 2      # Cerrar tras 2 éxitos consecutivos
  timeout: 30s              # Tiempo en estado "abierto"
  half_open_requests: 1     # Requests de prueba en "medio abierto"
```

**Comportamiento del Circuit Breaker:**

1. **Cerrado (normal):** Todas las requests pasan
2. **Abierto (falla):** Devolver 503 inmediatamente, no llamar al backend
3. **Medio abierto (prueba):** Permitir 1 request de prueba

**Fallback cuando el servicio falla:**

```json
{
  "status": "degraded",
  "message": "El servicio de mensajería está temporalmente no disponible. Su mensaje será procesado cuando se recupere el servicio.",
  "retry_after": 60
}
```

---

### 📝 Entregable Fase 2

Crear documento `entregables/02-contrato-api.md` con:

```markdown
# Contrato API: Servicio Buzón

## Endpoints

### POST /v1/mensajes
[Especificación completa]

### GET /v1/mensajes
[Especificación completa]

### GET /v1/mensajes/{id}
[Especificación completa]

### PATCH /v1/mensajes/{id}/estado
[Especificación completa]

## Códigos de error

| Código | Situación |
|--------|-----------|
| ... | ... |

## Configuración de resiliencia

- Timeouts
- Circuit Breaker
- Fallback strategy
```

---

## Fase 3: Elegir datos propios del servicio

### 🎯 Actividad grupal (25 minutos)

#### Análisis de datos actuales

**Tabla actual `messages` en PostgreSQL monolito:**

```sql
CREATE TABLE messages (
    id SERIAL PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    email VARCHAR(255) NOT NULL,
    phone VARCHAR(50),
    company VARCHAR(255),
    subject VARCHAR(500) NOT NULL,
    message TEXT NOT NULL,
    status VARCHAR(50) DEFAULT 'pending',
    origin VARCHAR(50),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    responded_at TIMESTAMP,
    responded_by VARCHAR(255),
    internal_notes TEXT
);
```

#### Decisiones de diseño

**1. Tipo de base de datos**

Opciones:
- **PostgreSQL (RDS):** Mantener SQL, familiar para el equipo
- **DynamoDB:** NoSQL, escalabilidad automática, serverless-friendly
- **S3 + Athena:** Para mensajes archivados, consultas analíticas

**Para este lab, usaremos DynamoDB porque:**
- El Buzón no necesita JOINs complejos
- Escalabilidad automática ante picos
- Integración natural con Lambda
- Bajo costo para volúmenes bajos/medios
- Preparación para arquitectura serverless

**2. Diseño de tabla DynamoDB**

```
Tabla: cloudcuyo-mensajes

Partition Key: mensaje_id (String)
Sort Key: N/A (acceso directo por ID)

GSI-1: EmailIndex
  Partition Key: email (String)
  Sort Key: fecha_recepcion (String, ISO 8601)

GSI-2: EstadoFechaIndex
  Partition Key: estado (String)
  Sort Key: fecha_recepcion (String, ISO 8601)
```

**Ejemplo de item:**

```json
{
  "mensaje_id": "MSG-2026-06-001234",
  "nombre": "Juan Pérez",
  "email": "juan@example.com",
  "telefono": "+54 261 123 4567",
  "empresa": "Acme Corp",
  "asunto": "Consulta sobre hosting",
  "mensaje": "Necesito información sobre planes de hosting...",
  "estado": "pendiente",
  "origen": "web",
  "fecha_recepcion": "2026-06-07T19:45:00Z",
  "fecha_actualizacion": "2026-06-07T19:45:00Z",
  "fecha_respuesta": null,
  "respondido_por": null,
  "notas_internas": null,
  "metadata": {
    "ip_origen": "190.12.34.56",
    "user_agent": "Mozilla/5.0..."
  }
}
```

**3. Patrones de acceso**

| Caso de uso | Patrón DynamoDB |
|-------------|-----------------|
| Obtener mensaje por ID | GetItem con `mensaje_id` |
| Listar mensajes por estado | Query en GSI-2 con `estado` + filtro fecha |
| Buscar mensajes de un email | Query en GSI-1 con `email` |
| Actualizar estado | UpdateItem en `mensaje_id` |
| Crear mensaje | PutItem |

**4. Datos que NO se copian al microservicio**

El servicio Buzón **no debe duplicar** datos de:
- Clientes (tabla `customers`)
- Soluciones (tabla `solutions`)
- Pagos (tabla `payments`)

Si necesita información de clientes, debe:
1. **Consultar vía API** al servicio de Clientes (si existe)
2. **Guardar solo el identificador** (ej: `customer_code`) sin duplicar datos

**Principio:** Un microservicio no debe ser dueño de datos ajenos.

---

### 📝 Entregable Fase 3

Crear documento `entregables/03-modelo-datos.md` con:

```markdown
# Modelo de Datos: Servicio Buzón

## Decisión de tecnología
[DynamoDB, PostgreSQL RDS, otro]

## Esquema de tabla(s)

### Tabla principal
[Definición completa]

### Índices secundarios
[GSI-1, GSI-2, etc.]

## Patrones de acceso

| Caso de uso | Query/Scan | Índice |
|-------------|------------|--------|
| ... | ... | ... |

## Datos excluidos

Lista de datos que NO se copian al microservicio:
- ...
- ...

## Migración desde tabla `messages` actual

Estrategia para migrar datos existentes:
[Descripción]
```

---

## Fase 4: Dibujar el flujo principal

### 🎯 Actividad grupal (30 minutos)

Diseñar el diagrama de secuencia del flujo principal: **"Usuario envía mensaje de contacto"**.

#### Flujo actual (Monolito)

```
Usuario → CloudFront → ALB → EC2 Portal → PostgreSQL
                                         ↓
                              Renderiza respuesta
```

**Problemas:**
- Todo acoplado en una sola aplicación
- Falla DB → falla todo el portal
- Pico de mensajes → sobrecarga del portal
- Difícil escalar solo el buzón

#### Flujo objetivo (Microservicio)

```
┌─────────┐
│ Usuario │
└────┬────┘
     │ 1. POST /contacto
     v
┌────────────────┐
│  CloudFront    │
│  (Frontend)    │
└───────┬────────┘
        │ 2. POST /v1/mensajes
        v
┌──────────────────────┐
│  API Gateway         │
│  + WAF + Rate Limit  │
└──────────┬───────────┘
           │ 3. Invoke
           v
┌──────────────────────┐
│  Lambda Function     │
│  procesarMensaje()   │
└──────────┬───────────┘
           │ 4. PutItem
           v
┌──────────────────────┐
│  DynamoDB            │
│  cloudcuyo-mensajes  │
└──────────┬───────────┘
           │ 5. DynamoDB Stream
           v
┌──────────────────────┐
│  Lambda Trigger      │
│  notificarMensaje()  │
└──────────┬───────────┘
           │ 6. Publish
           v
┌──────────────────────┐
│  SNS Topic           │
│  mensajes-recibidos  │
└──────────┬───────────┘
           │ 7. Notify
           ├──────────────────┐
           v                  v
    ┌───────────┐      ┌──────────┐
    │    SES    │      │  Slack   │
    │ (Email)   │      │  Webhook │
    └───────────┘      └──────────┘
```

#### Descripción paso a paso

**1. Usuario envía formulario**
- Frontend (CloudFront/S3) captura datos del formulario `contacto.html`
- JavaScript valida campos antes de enviar

**2. Request a API Gateway**
```javascript
fetch('https://api.cloudcuyo.com/buzon/v1/mensajes', {
  method: 'POST',
  headers: { 'Content-Type': 'application/json' },
  body: JSON.stringify({
    nombre: 'Juan Pérez',
    email: 'juan@example.com',
    asunto: 'Consulta',
    mensaje: 'Hola...'
  })
})
```

**3. API Gateway procesa request**
- **WAF:** Valida que no sea tráfico malicioso
- **Rate Limiting:** 10 requests/minuto por IP
- **Validación de esquema:** JSON schema validation
- **Invoca Lambda**

**4. Lambda procesa y guarda en DynamoDB**
```python
import boto3
import uuid
from datetime import datetime

def handler(event, context):
    # Parsear body
    data = json.loads(event['body'])
    
    # Validar datos
    if not validate_email(data['email']):
        return {
            'statusCode': 400,
            'body': json.dumps({
                'status': 'error',
                'error': {
                    'code': 'INVALID_EMAIL',
                    'message': 'Email inválido'
                }
            })
        }
    
    # Generar ID único
    mensaje_id = f"MSG-{datetime.now().strftime('%Y-%m')}-{uuid.uuid4().hex[:6]}"
    
    # Guardar en DynamoDB
    dynamodb = boto3.resource('dynamodb')
    table = dynamodb.Table('cloudcuyo-mensajes')
    
    item = {
        'mensaje_id': mensaje_id,
        'nombre': data['nombre'],
        'email': data['email'],
        'asunto': data['asunto'],
        'mensaje': data['mensaje'],
        'estado': 'pendiente',
        'fecha_recepcion': datetime.now().isoformat()
    }
    
    table.put_item(Item=item)
    
    # Responder
    return {
        'statusCode': 201,
        'body': json.dumps({
            'status': 'success',
            'data': {
                'mensaje_id': mensaje_id,
                'fecha_recepcion': item['fecha_recepcion']
            }
        })
    }
```

**5. DynamoDB Stream dispara evento**
- DynamoDB Stream captura el nuevo mensaje
- Dispara Lambda `notificarMensaje()`

**6. Lambda publica a SNS**
```python
def handler(event, context):
    for record in event['Records']:
        if record['eventName'] == 'INSERT':
            mensaje = record['dynamodb']['NewImage']
            
            sns = boto3.client('sns')
            sns.publish(
                TopicArn='arn:aws:sns:us-east-1:xxx:mensajes-recibidos',
                Subject=f"Nuevo mensaje: {mensaje['asunto']['S']}",
                Message=json.dumps(mensaje)
            )
```

**7. SNS notifica a múltiples destinos**
- **Email (SES):** Notifica al equipo de atención al cliente
- **Slack Webhook:** Notifica en canal #atencion-cliente
- **Futuro:** SMS, dashboard en tiempo real, etc.

---

#### Ventajas de esta arquitectura

✅ **Escalabilidad independiente:** Lambda escala automáticamente con el volumen de mensajes

✅ **Resiliencia:** Si falla DynamoDB, Circuit Breaker evita cascada de errores al portal

✅ **Desacoplamiento:** El portal frontend no sabe nada de cómo se procesan los mensajes

✅ **Observabilidad:** CloudWatch Logs + X-Ray para tracing distribuido

✅ **Extensibilidad:** Agregar nuevos suscriptores al SNS Topic sin tocar el core

✅ **Bajo costo:** Pago por uso (Lambda + DynamoDB on-demand)

---

#### Modos de falla y Circuit Breaker

**Escenario 1: Lambda falla temporalmente**
```
API Gateway → Lambda [FALLA] → Retry 3 veces → 503 Service Unavailable
                                               ↓
                                    Frontend muestra mensaje:
                                    "Servicio temporalmente no disponible.
                                     Por favor reintente en unos minutos."
```

**Escenario 2: DynamoDB throttling**
```
Lambda → DynamoDB [THROTTLED] → Exponential backoff → Retry
                                                      ↓
                                           Si falla definitivamente:
                                           500 Internal Server Error
```

**Escenario 3: Circuit Breaker abierto**
```
Frontend → API Gateway [Circuit OPEN] → 503 Immediately
                                        ↓
                                No llama a Lambda
                                Responde fallback inmediato
```

**Implementación de Circuit Breaker en frontend:**

```javascript
class CircuitBreaker {
  constructor() {
    this.state = 'CLOSED';  // CLOSED | OPEN | HALF_OPEN
    this.failureCount = 0;
    this.failureThreshold = 3;
    this.timeout = 30000;  // 30 segundos
  }
  
  async call(fn) {
    if (this.state === 'OPEN') {
      // No llamar al backend, devolver fallback
      throw new Error('Circuit breaker is OPEN');
    }
    
    try {
      const result = await fn();
      this.onSuccess();
      return result;
    } catch (error) {
      this.onFailure();
      throw error;
    }
  }
  
  onSuccess() {
    this.failureCount = 0;
    this.state = 'CLOSED';
  }
  
  onFailure() {
    this.failureCount++;
    if (this.failureCount >= this.failureThreshold) {
      this.state = 'OPEN';
      setTimeout(() => {
        this.state = 'HALF_OPEN';
        this.failureCount = 0;
      }, this.timeout);
    }
  }
}
```

---

### 📝 Entregable Fase 4

Crear diagrama `entregables/04-diagrama-flujo.md` (o `.png`) con:

1. **Diagrama de secuencia** del flujo principal
2. **Componentes AWS involucrados:**
   - CloudFront
   - API Gateway
   - Lambda (2 funciones)
   - DynamoDB
   - SNS
   - SES/Slack
3. **Tiempos de timeout en cada paso**
4. **Estrategia de retry y Circuit Breaker**
5. **Mensajes de error por cada modo de falla**

Pueden usar:
- **Mermaid:** Para diagramas en Markdown
- **Draw.io / Excalidraw:** Para diagramas visuales
- **ASCII art:** Para simplicidad

**Ejemplo con Mermaid:**

```markdown
# Diagrama de Flujo: Envío de Mensaje

\`\`\`mermaid
sequenceDiagram
    participant U as Usuario
    participant CF as CloudFront
    participant APIGW as API Gateway
    participant L1 as Lambda<br/>procesarMensaje
    participant DB as DynamoDB
    participant L2 as Lambda<br/>notificar
    participant SNS as SNS Topic
    participant SES as SES
    
    U->>CF: POST /contacto
    CF->>APIGW: POST /v1/mensajes
    APIGW->>APIGW: WAF + Rate Limit
    APIGW->>L1: Invoke (timeout: 10s)
    L1->>L1: Validar datos
    L1->>DB: PutItem (timeout: 3s)
    DB-->>L1: Success
    L1-->>APIGW: 201 Created
    APIGW-->>CF: Response
    CF-->>U: Confirmación
    
    Note over DB,L2: DynamoDB Stream
    DB->>L2: Nuevo mensaje
    L2->>SNS: Publish
    SNS->>SES: Enviar email
\`\`\`
```

---

## Fase 5: Discusión de Anti-patrones y Decisión

### 🎯 Actividad grupal (20 minutos)

Discutir los siguientes anti-patrones frecuentes y cómo evitarlos:

#### ❌ Anti-patrón 1: Compartir base de datos

**Problema:**
```
Servicio Buzón ──┐
                 ├──→ PostgreSQL compartida
Servicio Portal ─┘
```

**Por qué es malo:**
- Acoplamiento fuerte
- Cambios en esquema afectan a todos
- Difícil escalar independientemente

**Solución:**
- Cada servicio tiene su propia base de datos
- Comunicación vía APIs o eventos

---

#### ❌ Anti-patrón 2: Dividir por capas técnicas

**Problema:**
```
Servicio Frontend
Servicio Backend
Servicio Database
```

**Por qué es malo:**
- No sigue Bounded Contexts de negocio
- Un cambio de funcionalidad afecta las 3 capas

**Solución:**
- Dividir por dominios de negocio (Buzón, Catálogo, Clientes)
- Cada servicio tiene su frontend, backend y datos

---

#### ❌ Anti-patrón 3: Sin observabilidad

**Problema:**
- Error en producción → no se sabe en qué servicio falló
- No hay tracing distribuido
- Imposible debuggear

**Solución:**
- **Correlation ID:** Pasar ID único en cada request
- **Structured logging:** JSON logs con contexto
- **Distributed tracing:** AWS X-Ray
- **Métricas:** CloudWatch Metrics

**Ejemplo de Correlation ID:**

```javascript
// Frontend genera correlation-id
const correlationId = uuid.v4();

fetch('/v1/mensajes', {
  headers: {
    'X-Correlation-ID': correlationId
  }
});

// Lambda recibe y propaga
def handler(event, context):
    correlation_id = event['headers'].get('X-Correlation-ID')
    logger.info('Processing message', extra={
        'correlation_id': correlation_id
    })
```

---

#### ❌ Anti-patrón 4: Todo síncrono

**Problema:**
```
Usuario → API → Servicio A → Servicio B → Servicio C → Servicio D
                 (espera)     (espera)     (espera)     (espera)
```

- Latencia acumulada
- Si un servicio falla, falla todo

**Solución:**
- Usar comunicación **asíncrona** cuando sea posible
- **Patrón Saga** para transacciones distribuidas
- **Event-driven architecture**

**Ejemplo en Buzón:**
```
Usuario → API Buzón → 201 Created (responde inmediato)
                ↓
           DynamoDB Stream → SNS → SES (asíncrono)
```

---

#### ❌ Anti-patrón 5: Equipo chico, operación gigante

**Problema:**
- Equipo de 3 personas mantiene 20 microservicios
- Complejidad operativa insostenible

**Decisión:**
- **Empezar con monolito bien estructurado**
- Separar microservicios solo cuando:
  - Hay equipos autónomos
  - Hay escalabilidad diferencial
  - Hay ciclos de cambio independientes

**Para CloudCuyo:**
- Equipo actual: 5 personas
- Primer microservicio: Buzón (bajo riesgo)
- Siguiente: API Catálogo (si crece el equipo)

---

### 📝 Entregable Fase 5

Crear documento `entregables/05-decision-tecnica.md` con:

```markdown
# Decisión Técnica: ¿Separamos el Buzón?

## Análisis de conveniencia

### ✅ A favor de separar
- [Argumentos]

### ⚠️ En contra de separar
- [Riesgos]

## Decisión del equipo
[SÍ | NO | NO TODAVÍA]

## Justificación
[Explicar por qué]

## Plan de implementación (si SÍ)

### Fase 1: Preparación (Semana 1-2)
- [ ] Definir contrato de API
- [ ] Crear tabla DynamoDB
- [ ] Implementar Lambda procesarMensaje

### Fase 2: Deploy canario (Semana 3)
- [ ] Desplegar API Gateway
- [ ] Rutear 5% tráfico al nuevo servicio
- [ ] Monitorear métricas y errores

### Fase 3: Rollout completo (Semana 4)
- [ ] Rutear 100% tráfico
- [ ] Deprecar endpoint viejo
- [ ] Migrar datos históricos

### Fase 4: Optimización (Semana 5+)
- [ ] Implementar notificaciones SNS
- [ ] Agregar Circuit Breaker
- [ ] Mejorar observabilidad
```

---

## Entregables finales del lab

Al finalizar el lab, cada grupo debe entregar:

1. **`01-bounded-context.md`**: Análisis de límites del servicio
2. **`02-contrato-api.md`**: Especificación completa de la API REST
3. **`03-modelo-datos.md`**: Diseño de base de datos y patrones de acceso
4. **`04-diagrama-flujo.md`** (o `.png`): Diagrama de secuencia del flujo principal
5. **`05-decision-tecnica.md`**: Decisión fundamentada sobre separar o no el Buzón

**Formato de entrega:**
- Carpeta `entregables/` en el repositorio del grupo
- Presentación de 10 minutos explicando las decisiones
- Q&A con el instructor y otros grupos

---

## Extensión opcional: Implementar el servicio

Para grupos avanzados que quieran ir más allá del diseño, se propone implementar el servicio Buzón en AWS:

### Infraestructura como código (Terraform)

Crear `microservices/buzon-api/infra/terraform/`:

```hcl
# DynamoDB Table
resource "aws_dynamodb_table" "mensajes" {
  name         = "cloudcuyo-mensajes"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "mensaje_id"
  
  attribute {
    name = "mensaje_id"
    type = "S"
  }
  
  attribute {
    name = "email"
    type = "S"
  }
  
  attribute {
    name = "estado"
    type = "S"
  }
  
  attribute {
    name = "fecha_recepcion"
    type = "S"
  }
  
  global_secondary_index {
    name            = "EmailIndex"
    hash_key        = "email"
    range_key       = "fecha_recepcion"
    projection_type = "ALL"
  }
  
  global_secondary_index {
    name            = "EstadoFechaIndex"
    hash_key        = "estado"
    range_key       = "fecha_recepcion"
    projection_type = "ALL"
  }
  
  stream_enabled   = true
  stream_view_type = "NEW_IMAGE"
  
  tags = {
    Environment = "production"
    Service     = "buzon"
  }
}

# Lambda Function
resource "aws_lambda_function" "procesar_mensaje" {
  filename      = "lambda.zip"
  function_name = "cloudcuyo-buzon-procesar"
  role          = aws_iam_role.lambda_exec.arn
  handler       = "index.handler"
  runtime       = "python3.11"
  timeout       = 10
  
  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.mensajes.name
    }
  }
}

# API Gateway
resource "aws_apigatewayv2_api" "buzon" {
  name          = "cloudcuyo-buzon-api"
  protocol_type = "HTTP"
  
  cors_configuration {
    allow_origins = ["https://cloudcuyo.com"]
    allow_methods = ["GET", "POST", "PATCH"]
    allow_headers = ["Content-Type", "X-Correlation-ID"]
  }
}

# SNS Topic
resource "aws_sns_topic" "mensajes_recibidos" {
  name = "cloudcuyo-mensajes-recibidos"
}
```

### Código de Lambda Functions

Crear `microservices/buzon-api/lambda/`:

**`procesar_mensaje/index.py`:**
```python
import json
import boto3
import uuid
from datetime import datetime
from email_validator import validate_email, EmailNotValidError

dynamodb = boto3.resource('dynamodb')
table = dynamodb.Table('cloudcuyo-mensajes')

def handler(event, context):
    try:
        # Parse body
        body = json.loads(event.get('body', '{}'))
        
        # Validate required fields
        required_fields = ['nombre', 'email', 'asunto', 'mensaje']
        for field in required_fields:
            if field not in body:
                return error_response(400, 'MISSING_FIELD', f'Campo requerido: {field}')
        
        # Validate email
        try:
            validate_email(body['email'])
        except EmailNotValidError:
            return error_response(400, 'INVALID_EMAIL', 'Formato de email inválido')
        
        # Generate unique ID
        mensaje_id = f"MSG-{datetime.now().strftime('%Y-%m')}-{uuid.uuid4().hex[:6].upper()}"
        
        # Prepare item
        item = {
            'mensaje_id': mensaje_id,
            'nombre': body['nombre'],
            'email': body['email'],
            'telefono': body.get('telefono', ''),
            'empresa': body.get('empresa', ''),
            'asunto': body['asunto'],
            'mensaje': body['mensaje'],
            'estado': 'pendiente',
            'origen': body.get('origen', 'web'),
            'fecha_recepcion': datetime.now().isoformat(),
            'fecha_actualizacion': datetime.now().isoformat()
        }
        
        # Save to DynamoDB
        table.put_item(Item=item)
        
        # Return success
        return {
            'statusCode': 201,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'
            },
            'body': json.dumps({
                'status': 'success',
                'data': {
                    'mensaje_id': mensaje_id,
                    'fecha_recepcion': item['fecha_recepcion'],
                    'estado': 'pendiente'
                }
            })
        }
        
    except Exception as e:
        print(f"Error: {str(e)}")
        return error_response(500, 'INTERNAL_ERROR', 'Error procesando el mensaje')

def error_response(status_code, error_code, message):
    return {
        'statusCode': status_code,
        'headers': {
            'Content-Type': 'application/json',
            'Access-Control-Allow-Origin': '*'
        },
        'body': json.dumps({
            'status': 'error',
            'error': {
                'code': error_code,
                'message': message
            }
        })
    }
```

**`notificar_mensaje/index.py`:**
```python
import json
import boto3

sns = boto3.client('sns')
SNS_TOPIC_ARN = 'arn:aws:sns:us-east-1:ACCOUNT:cloudcuyo-mensajes-recibidos'

def handler(event, context):
    for record in event['Records']:
        if record['eventName'] == 'INSERT':
            mensaje = record['dynamodb']['NewImage']
            
            # Extract fields
            mensaje_id = mensaje['mensaje_id']['S']
            nombre = mensaje['nombre']['S']
            email = mensaje['email']['S']
            asunto = mensaje['asunto']['S']
            
            # Publish to SNS
            sns.publish(
                TopicArn=SNS_TOPIC_ARN,
                Subject=f'Nuevo mensaje: {asunto}',
                Message=json.dumps({
                    'mensaje_id': mensaje_id,
                    'nombre': nombre,
                    'email': email,
                    'asunto': asunto
                }, indent=2)
            )
            
            print(f"Notificación enviada para mensaje {mensaje_id}")
    
    return {'statusCode': 200}
```

---

## Recursos adicionales

### Documentación AWS
- [AWS Lambda Best Practices](https://docs.aws.amazon.com/lambda/latest/dg/best-practices.html)
- [DynamoDB Design Patterns](https://docs.aws.amazon.com/amazondynamodb/latest/developerguide/best-practices.html)
- [API Gateway with Lambda](https://docs.aws.amazon.com/apigateway/latest/developerguide/api-gateway-create-api-as-simple-proxy-for-lambda.html)
- [AWS X-Ray Distributed Tracing](https://docs.aws.amazon.com/xray/latest/devguide/xray-concepts.html)

### Patrones de microservicios
- [Circuit Breaker Pattern](https://martinfowler.com/bliki/CircuitBreaker.html)
- [Saga Pattern](https://microservices.io/patterns/data/saga.html)
- [API Gateway Pattern](https://microservices.io/patterns/apigateway.html)
- [Database per Service](https://microservices.io/patterns/data/database-per-service.html)

### Libros recomendados
- *Building Microservices* - Sam Newman
- *Designing Data-Intensive Applications* - Martin Kleppmann
- *Domain-Driven Design* - Eric Evans

---

## Conclusión

Este lab te guió por el proceso de **diseño de microservicios** aplicado a un caso real: separar el Buzón de contacto de CloudCuyo como servicio independiente.

**Conceptos clave trabajados:**
✅ Bounded Context y límites funcionales  
✅ Contratos de API y versionado  
✅ Base de datos por servicio  
✅ Patrones de resiliencia (Circuit Breaker, timeouts, retries)  
✅ Observabilidad y tracing distribuido  
✅ Comunicación asíncrona con eventos  
✅ Anti-patrones frecuentes  

**Próximos pasos:**
- **Clase 8:** Serverless y MLOps - Implementar el Buzón como Lambda + API Gateway
- **Clase 9:** Contenedores y ECS - Deployar microservicios en contenedores
- **Clase 10:** Observabilidad avanzada - CloudWatch, X-Ray, Application Insights

---

**¿Preguntas? Consultas a:** nicolas.pannucio@gmail.com

---

*Proyecto educativo — Formatec Cloud Course 2026*
