# LAB03 — RDS privado: Security Groups, secretos e IAM

**Curso:** Arquitectura e Ingeniería Cloud | C2 — FormaTEC 2026
**Duración estimada:** 120 minutos
**Modalidad:** individual o en parejas
**Región de referencia:** `us-east-1`
**Tema:** conectividad de red, Security Groups, RDS PostgreSQL, Secrets Manager, IAM y TLS

---

## 1. Contexto

La infraestructura de LAB02 ya tiene cuatro EC2 privadas distribuidas en dos grupos:

- `backend-a-01` y `backend-a-02`;
- `backend-b-01` y `backend-b-02`.

En este laboratorio se agrega una base PostgreSQL privada en Amazon RDS. El ejercicio comienza con una regla de conectividad demasiado amplia: las cuatro EC2 pueden alcanzar el puerto TCP `5432` de RDS.

El objetivo es aplicar controles progresivos hasta obtener esta matriz:

| Instancia | TCP 5432 hacia RDS | Recuperar secreto | Consultar PostgreSQL |
|---|---:|---:|---:|
| `backend-a-01` | Denegado | Denegado | Denegado |
| `backend-a-02` | Denegado | Denegado | Denegado |
| `backend-b-01` | Permitido | Permitido | Permitido |
| `backend-b-02` | Permitido | Permitido | Permitido |

Arquitectura inicial:

```text
backend-a-01 ─┐
backend-a-02 ─┼── TCP 5432 permitido inicialmente ──> RDS PostgreSQL privada
backend-b-01 ─┤
backend-b-02 ─┘
```

Arquitectura objetivo:

```text
backend-a-01 ──X
backend-a-02 ──X                         ┌──────────────┐
                                         │ RDS privada  │
backend-b-01 ── SG-BACKEND-B ──────────>│ SG-RDS:5432  │
backend-b-02 ── SG-BACKEND-B            └──────────────┘
```

La conectividad de red, los permisos IAM y la autenticación PostgreSQL son controles diferentes. Una instancia puede resolver el endpoint, pero no tener permiso para leer el secreto. También puede leer un secreto, pero no tener conectividad hacia RDS.

> Una regla con `/32` no es la única forma de limitar una EC2. En una misma VPC, la solución recomendada es referenciar un Security Group como origen lógico. Así no se depende de una IP privada que puede cambiar al reemplazar una instancia.

---

## 2. Objetivos de aprendizaje

Al finalizar podrás:

1. identificar el riesgo de una regla de red demasiado amplia;
2. construir una matriz de acceso antes de modificar la infraestructura;
3. restringir TCP `5432` usando un Security Group como origen lógico;
4. diferenciar CIDR, `/32` y referencia a Security Group;
5. verificar conectividad positiva y negativa desde las cuatro EC2;
6. utilizar un secreto administrado por RDS en Secrets Manager;
7. asignar `GetSecretValue` únicamente a los roles de `backend-b`;
8. conectarte a PostgreSQL mediante TLS sin imprimir la password;
9. diferenciar Secrets Manager de IAM Database Authentication;
10. interpretar si un error pertenece a red, IAM, TLS o SQL;
11. limpiar solamente el root de RDS al finalizar.

---

## 3. Alcance y estado inicial

El workflow administra únicamente:

```text
labs/m4-c1-lab/terraform-rds/
```

El state remoto es independiente:

```text
m4-c1/<student_identity>/rds.tfstate
```

El root RDS descubre la VPC y los recursos de LAB02. No recrea la fundación.

Terraform deja preparada una RDS con:

- subnets privadas de base de datos;
- `publicly_accessible = false`;
- almacenamiento cifrado;
- backups con retención de un día;
- `multi_az = false` por alcance y costo del ejercicio;
- Security Group de RDS con TCP `5432` permitido inicialmente desde el CIDR de la VPC;
- Security Group vacío preparado para asociarse a `backend-b`;
- ese Security Group asociado únicamente a las ENI de `backend-b`;
- policies IAM para que solo `backend-b` pueda recuperar el secreto administrado por RDS;
- parámetro `rds.force_ssl = 1`.

El permiso inicial desde el CIDR de la VPC es amplio dentro de la red del laboratorio, pero RDS continúa siendo privada y no tiene exposición pública.

---

## 4. Prerrequisitos

Completá LAB01 y LAB02 antes de comenzar. Confirmá:

- existen cuatro EC2 privadas;
- las cuatro aparecen `Online` en Systems Manager;
- `psql`, `jq` y AWS CLI están disponibles;
- `STUDENT_IDENTITY` coincide con LAB02;
- el Environment `lab` contiene `AWS_ROLE_ARN`, `AWS_REGION`, `STUDENT_IDENTITY` y `TF_STATE_BUCKET`;
- el role OIDC tiene permisos para administrar los recursos RDS del laboratorio.

No ejecutes el workflow RDS hasta que las cuatro instancias estén disponibles en SSM.

---

## 5. Ejecutar el workflow RDS

En GitHub:

1. Abrí **Actions**.
2. Seleccioná **M4-C1 RDS Network Security**.
3. Ejecutá primero el workflow con `action = plan`.
4. Revisá que utilice `terraform-rds/` y su state independiente.
5. Confirmá que no intente destruir la VPC, las EC2 ni los buckets.
6. Ejecutá nuevamente con `action = apply`.

El plan debe incluir, entre otros:

```text
aws_db_subnet_group.rds
aws_security_group.rds
aws_security_group.backend_b_source
aws_network_interface_sg_attachment.backend_b_source
aws_vpc_security_group_egress_rule.backend_to_rds
aws_db_parameter_group.postgres
aws_db_instance.rds
aws_iam_role_policy.backend_b_rds_secret
```

Resultado esperado aproximado:

```text
Apply complete! Resources: 10 added, 0 changed, 0 destroyed.
```

La instancia resultante debe ser privada. El root inicial deja TCP `5432` abierto al CIDR de la VPC para que las cuatro EC2 puedan realizar la primera prueba.

---

## 6. Fase 1 — Probar el estado permisivo

Anotá los outputs del workflow:

```text
rds_endpoint
rds_port
rds_secret_arn
rds_security_group_id
backend_b_source_security_group_id
```

Definí variables de sesión en una EC2:

```bash
export RDS_ENDPOINT="<rds_endpoint>"
export RDS_PORT="5432"
export RDS_SECRET_ARN="<rds_secret_arn>"
export AWS_REGION="us-east-1"
```

Desde cada una de las cuatro instancias ejecutá una comprobación TCP:

```bash
nc -vz "$RDS_ENDPOINT" "$RDS_PORT"
```

Si `nc` no está disponible, utilizá:

```bash
timeout 5 bash -c "</dev/tcp/${RDS_ENDPOINT}/${RDS_PORT}" && echo TCP_REACHABLE
```

Resultado esperado inicial:

| Instancia | Resultado inicial |
|---|---|
| `backend-a-01` | `TCP_REACHABLE` |
| `backend-a-02` | `TCP_REACHABLE` |
| `backend-b-01` | `TCP_REACHABLE` |
| `backend-b-02` | `TCP_REACHABLE` |

Checkpoint:

- ¿Qué permite la regla inicial?
- ¿Por qué una RDS privada sigue necesitando controles de Security Group?
- ¿Qué diferencia hay entre alcanzar el puerto y autenticarse en PostgreSQL?
- ¿Qué riesgo existe si cualquier instancia de la VPC puede alcanzar RDS?

---

## 7. Fase 2 — Construir la matriz requerida

Antes de cambiar reglas, completá la matriz objetivo:

| Instancia | TCP 5432 | `GetSecretValue` | Login PostgreSQL | Consulta SQL |
|---|---|---|---|---|
| `backend-a-01` | Denegado | Denegado | Denegado | Denegado |
| `backend-a-02` | Denegado | Denegado | Denegado | Denegado |
| `backend-b-01` | Permitido | Permitido | Permitido | Permitido |
| `backend-b-02` | Permitido | Permitido | Permitido | Permitido |

Esta matriz será el criterio de aceptación del laboratorio.

---

## 8. Fase 3 — Restringir el acceso mediante Security Groups

El root ya creó un Security Group dedicado y lo asoció a las ENI de `backend-b`:

```text
SG-BACKEND-B-RDS-SOURCE
├── ENI de backend-b-01
└── ENI de backend-b-02
```

En la consola de EC2 modificá el Security Group de RDS:

1. Identificá la regla inbound TCP `5432` cuyo origen es el CIDR de la VPC.
2. Eliminá esa regla amplia.
3. Agregá una regla inbound:

```text
Protocol: TCP
Port: 5432
Source: SG-BACKEND-B-RDS-SOURCE
```

No agregues una regla basada en:

```text
0.0.0.0/0
La IP /32 de una sola instancia
El CIDR completo de la VPC
```

Una referencia a Security Group expresa mejor la pertenencia lógica de las instancias. Si una EC2 se reemplaza y conserva el SG, no es necesario actualizar una IP en RDS.

> Esta modificación se realiza como parte de la actividad del alumno. Si después se ejecuta un nuevo `terraform apply` sobre el mismo root, Terraform puede restaurar el estado declarado inicialmente. Primero completá las pruebas y luego ejecutá cleanup.

---

## 9. Fase 4 — Verificar la segmentación de red

Ejecutá nuevamente la prueba TCP desde las cuatro instancias.

Resultado esperado:

| Instancia | Resultado final de red |
|---|---|
| `backend-a-01` | `TCP_BLOCKED_OR_UNREACHABLE` |
| `backend-a-02` | `TCP_BLOCKED_OR_UNREACHABLE` |
| `backend-b-01` | `TCP_REACHABLE` |
| `backend-b-02` | `TCP_REACHABLE` |

Este resultado prueba únicamente la capa de red:

> Solo `backend-b-01` y `backend-b-02` pueden alcanzar RDS por TCP `5432`.

Todavía no demuestra que tengan permiso para recuperar el secreto ni que puedan ejecutar SQL.

---

## 10. Fase 5 — Secrets Manager e IAM

RDS crea y administra el secreto mediante:

```hcl
manage_master_user_password = true
```

La password no debe guardarse en Terraform ni en el repositorio.

El role IAM de cada instancia `backend-b` recibe únicamente:

```text
secretsmanager:DescribeSecret
secretsmanager:GetSecretValue
```

El recurso está limitado al secreto de esta RDS.

Desde `backend-b-01` verificá el acceso sin imprimir el valor:

```bash
aws secretsmanager describe-secret \
  --secret-id "$RDS_SECRET_ARN" \
  --region "$AWS_REGION" \
  --query '{Name:Name,ARN:ARN,RotationEnabled:RotationEnabled}'
```

El script de validación recupera el secreto en memoria y no imprime la password.

Para probar la separación IAM, ejecutá desde una instancia `backend-a` solamente una consulta de metadata o recuperación controlada. El resultado esperado para `GetSecretValue` es:

```text
AccessDenied
```

No copies ni imprimas el contenido del secreto.

---

## 11. Fase 6 — Inicializar y consultar PostgreSQL

Descargá los scripts:

```bash
sudo mkdir -p /opt/security-lab

sudo curl -fsSL \
  https://raw.githubusercontent.com/nicopannu/curso-cloud-formatec-c2-2026/main/labs/m4-c1-lab/scripts/inicializar-rds.sh \
  -o /opt/security-lab/inicializar-rds.sh

sudo curl -fsSL \
  https://raw.githubusercontent.com/nicopannu/curso-cloud-formatec-c2-2026/main/labs/m4-c1-lab/scripts/validar-rds.sh \
  -o /opt/security-lab/validar-rds.sh

sudo chmod 750 /opt/security-lab/*.sh
```

Desde `backend-b-01`, inicializá el dato de prueba:

```bash
sudo /opt/security-lab/inicializar-rds.sh \
  "$RDS_ENDPOINT" \
  "$RDS_PORT" \
  "$RDS_SECRET_ARN"
```

El script crea o actualiza:

```sql
lab_access(id integer primary key, mensaje text not null)
```

Luego ejecutá desde cada instancia:

```bash
sudo /opt/security-lab/validar-rds.sh \
  "$RDS_ENDPOINT" \
  "$RDS_PORT" \
  "$RDS_SECRET_ARN"
```

En `backend-b` se espera:

```text
TCP_REACHABLE
SECRET_RETRIEVED_WITHOUT_PRINTING_PASSWORD
1|dato de prueba del laboratorio
```

En `backend-a`, la validación debe detenerse en la capa TCP y no intentar leer el secreto.

La conexión utiliza:

```text
sslmode=require
```

Si se prueba con TLS deshabilitado, PostgreSQL debe rechazar la conexión debido a `rds.force_ssl = 1`.

---

## 12. Secrets Manager e IAM Database Authentication

Estas son dos estrategias diferentes.

### Password administrada por RDS y Secrets Manager

```text
Role IAM de la EC2
    ↓ secretsmanager:GetSecretValue
Secrets Manager
    ↓ password administrada por RDS
PostgreSQL
```

En este laboratorio se implementa esta estrategia.

IAM autoriza a la EC2 a recuperar el secreto, pero PostgreSQL recibe una password para autenticar el login.

### IAM Database Authentication

```text
Role IAM de la EC2
    ↓ rds-db:connect
Token temporal
    ↓
Usuario PostgreSQL habilitado para IAM
```

Esta alternativa no recupera una password permanente desde Secrets Manager. Requiere habilitar IAM Database Authentication, crear un usuario PostgreSQL adecuado y asignar el permiso `rds-db:connect` al role.

Queda como extensión conceptual de este laboratorio. No forma parte del flujo obligatorio.

Checkpoint:

- ¿Qué permiso se utiliza con Secrets Manager?
- ¿Qué permiso se utilizaría con IAM Database Authentication?
- ¿Dónde se autentica el usuario en cada estrategia?
- ¿Qué control corresponde a red y cuál corresponde a identidad?
- ¿Qué ocurre si TCP está permitido pero `GetSecretValue` está denegado?

---

## 13. Interpretación de resultados

| Síntoma | Capa a revisar |
|---|---|
| Timeout TCP desde `backend-a` | Security Groups, rutas o endpoint |
| TCP funciona desde `backend-b` | La conectividad de red está permitida |
| `GetSecretValue AccessDenied` | Role IAM o policy del secreto |
| Login PostgreSQL rechazado | Usuario, password, base o TLS |
| Error de TLS | `sslmode` o `rds.force_ssl` |
| Backend-a puede leer el secreto | Policy IAM asociada al role equivocado |
| Backend-a puede llegar a RDS | Regla inbound demasiado amplia |
| Terraform quiere destruir la VPC | Se ejecutó el root equivocado |

No abras `0.0.0.0/0` ni SSH público para resolver un error.

---

## 14. Cleanup

Al finalizar las pruebas:

1. Ejecutá el workflow **M4-C1 RDS Network Security** con:

```text
action = destroy
```

2. Revisá el plan de destrucción.
3. Confirmá que afecte solamente el root RDS:
   - instancia RDS;
   - DB subnet group;
   - parameter group;
   - Security Groups del ejercicio;
   - attachments de `backend-b`;
   - regla egress backend→RDS;
   - policies IAM del secreto;
   - secreto administrado por RDS.

4. Ejecutá el destroy.
5. Verificá que no quede ninguna instancia RDS ni secreto del ejercicio.

No ejecutes el destroy de **M4-C1 Infra Deploy** mientras LAB02 siga siendo necesario.

---

## 15. Entregables

1. Link del run `plan`.
2. Link del run `apply`.
3. Outputs sin valores sensibles.
4. Matriz inicial y matriz final.
5. Diagrama con las cuatro EC2, el SG fuente de `backend-b`, el SG de RDS y RDS.
6. Evidencia de que las cuatro EC2 alcanzaban inicialmente TCP `5432`.
7. Evidencia de que solo `backend-b` alcanza TCP `5432` después del cambio.
8. Evidencia de RDS privada y cifrada.
9. Evidencia de Secrets Manager sin mostrar la password.
10. Evidencia de `AccessDenied` desde un role de `backend-a`.
11. Salida de `validar-rds.sh` desde las cuatro EC2.
12. Evidencia de la fila SQL desde `backend-b`.
13. Respuestas de los checkpoints.
14. Link o evidencia del cleanup.

No entregues:

```text
Passwords
Valores de secretos
Access keys
Tokens
Archivos .tfstate
Planes Terraform
```

---

## 16. Criterios de evaluación

| Criterio | Evidencia | Ponderación |
|---|---|---:|
| Matriz de acceso | Estado inicial y objetivo correctamente definidos | 15% |
| Security Groups | Solo `backend-b` alcanza TCP `5432` mediante referencia lógica | 30% |
| Pruebas negativas | `backend-a` queda bloqueado y el resultado se interpreta correctamente | 15% |
| IAM y Secrets Manager | Solo `backend-b` recupera el secreto sin exponer la password | 20% |
| PostgreSQL y TLS | Login, consulta SQL y `sslmode=require` funcionando | 10% |
| Cleanup | RDS y recursos sensibles eliminados sin destruir la fundación | 10% |

Errores críticos:

- dejar RDS accesible desde `0.0.0.0/0`;
- resolver el problema agregando una `/32` fija sin explicar su limitación;
- asignar `GetSecretValue` a `backend-a`;
- guardar passwords en Terraform o en el repositorio;
- abrir SSH público;
- destruir la fundación antes de terminar el laboratorio;
- confundir Secrets Manager con IAM Database Authentication;
- afirmar que `multi_az = false` representa alta disponibilidad productiva.

---

## 17. Cierre

Completá la frase:

> Al inicio, las cuatro EC2 podían alcanzar RDS porque __________. Después de modificar los Security Groups, solo `backend-b` llega porque __________. Secrets Manager resuelve __________. IAM controla __________. La conexión PostgreSQL todavía usa __________. IAM Database Authentication se diferencia porque __________.
