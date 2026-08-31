# LAB03 — RDS privado y segmentación de red

**Curso:** Arquitectura e Ingeniería Cloud | C2 — FormaTEC 2026
**Duración estimada:** 120 minutos
**Modalidad:** individual o en parejas
**Región de referencia:** `us-east-1`
**Tema:** Security Groups, RDS privado, Secrets Manager, TLS y pruebas desde EC2

---

## 1. Contexto

En LAB02 desplegaste una VPC con subnets públicas, subnets privadas para `backend-a` y `backend-b`, dos subnets reservadas para base de datos y cuatro EC2 privadas.

En este laboratorio vas a agregar una base de datos PostgreSQL administrada por Amazon RDS. La base de datos no tendrá IP pública. El acceso se controla en dos capas diferentes:

- **Red:** `SG-RDS` permite TCP 5432 únicamente desde el SG fuente dedicado asociado a `backend-b`.
- **Identidad:** solo los roles de `backend-b` pueden leer el secreto administrado por RDS.

La misma prueba se ejecuta desde instancias con el mismo sistema operativo y las mismas herramientas. El resultado cambia por la ruta de red y el role IAM, no por una diferencia de software.

```text
backend-a ──X── TCP 5432 ──> SG-RDS ──> RDS PostgreSQL
backend-b ───── TCP 5432 ──> SG-RDS ──> RDS PostgreSQL
     │                              │
     └── GetSecretValue permitido   └── secreto administrado por RDS
```

---

## 2. Objetivos de aprendizaje

Al finalizar podrás:

1. desplegar un RDS privado en un DB subnet group dedicado;
2. restringir el ingreso mediante un Security Group como origen lógico;
3. diferenciar conectividad TCP, autorización IAM y autenticación PostgreSQL;
4. usar un secreto administrado por RDS sin guardar passwords en Terraform;
5. exigir TLS con el parámetro `rds.force_ssl`;
6. probar un acceso permitido desde `backend-b`;
7. probar un bloqueo de red desde `backend-a`;
8. verificar que solo los roles de backend-b recuperen el secreto;
9. interpretar evidencia de red e identidad antes de corregir permisos;
10. destruir el root de RDS y verificar que no queden recursos sensibles.

---

## 3. Alcance y seguridad

El workflow de este laboratorio administra únicamente el root `terraform-rds/`. Su state remoto es independiente:

```text
m4-c1/<student_identity>/rds.tfstate
```

El root descubre la VPC, las subnets `Tier=db`, el Security Group backend y los roles creados por LAB02. No recrea la fundación.

Controles incluidos:

- `publicly_accessible = false`;
- DB subnet group con las dos subnets `db`;
- `SG-RDS` con TCP 5432 solo desde un SG fuente dedicado;
- SG fuente dedicado asociado únicamente a las ENI de backend-b;
- egress TCP 5432 agregado al SG backend únicamente hacia `SG-RDS`;
- almacenamiento RDS cifrado;
- backups con retención de un día para la práctica;
- password maestro administrado por RDS en Secrets Manager;
- `rds.force_ssl = 1`;
- `GetSecretValue` y `DescribeSecret` solo para `backend-b-01` y `backend-b-02`;
- sin SSH público, passwords en archivos, access keys ni datos sensibles versionados.

`multi_az = false` es una decisión de alcance y costo para esta práctica. No representa una arquitectura productiva de alta disponibilidad.

---

## 4. Prerrequisitos

Completá LAB01 y LAB02 antes de empezar. Confirmá:

- el workflow `M4-C1 Infra Deploy` ejecutó el foundation;
- existen cuatro EC2 privadas y sus roles;
- `STUDENT_IDENTITY` conserva exactamente el valor anterior;
- `AWS_ROLE_ARN`, `AWS_REGION` y `TF_STATE_BUCKET` existen en el Environment `lab`;
- el role OIDC tiene la policy `formatec-terraform-deploy`.

La policy del role OIDC debe incluir el statement adicional de RDS que se encuentra en:

```text
labs/m4-c1-lab/policies/terraform-deploy-policy.json
```

Si el role ya tenía una versión anterior de la policy, actualizá la policy administrada desde IAM antes de ejecutar este workflow. No agregues `AdministratorAccess`.

---

## 5. Actualizar la fundación

El root fundacional instala el cliente PostgreSQL en las EC2 durante el bootstrap. Ejecutá nuevamente el workflow `M4-C1 Infra Deploy` con:

```text
action = apply
```

Revisá el plan antes de aprobarlo. El cambio esperado es la instalación del paquete cliente en la configuración de User Data. Después de que las instancias estén listas, verificá por Session Manager que exista `psql`:

```bash
psql --version
jq --version
aws --version
```

Resultado esperado: se muestran las versiones instaladas y no se abre ningún puerto SSH.

> Si la actualización reemplaza una EC2 por un cambio de User Data, esperá que el SSM Agent vuelva a aparecer antes de continuar. No ejecutes el workflow RDS hasta tener disponibles las cuatro instancias necesarias.

---

## 6. Revisar el root RDS

Antes de aplicar, revisá:

```text
labs/m4-c1-lab/terraform-rds/versions.tf
labs/m4-c1-lab/terraform-rds/variables.tf
labs/m4-c1-lab/terraform-rds/locals.tf
labs/m4-c1-lab/terraform-rds/rds.tf
labs/m4-c1-lab/terraform-rds/outputs.tf
.github/workflows/m4-c1-rds-deploy.yml
```

Identificá:

- cómo se descubren las subnets `Tier=db`;
- qué Security Group es el origen de TCP 5432;
- dónde se exige `publicly_accessible = false`;
- dónde se exige cifrado;
- dónde se activa `rds.force_ssl`;
- cómo se obtiene el ARN del secreto sin imprimirlo;
- qué roles reciben `secretsmanager:GetSecretValue`.

El root no usa una password literal. `manage_master_user_password = true` permite que RDS cree y administre el secreto.

---

## 7. Ejecutar el workflow RDS

En GitHub:

1. Abrí **Actions**.
2. Seleccioná **M4-C1 RDS Network Security**.
3. Elegí **Run workflow**.
4. Ejecutá primero `plan`.
5. Revisá el plan y confirmá que no intente destruir la fundación.
6. Ejecutá nuevamente con `apply`.

El workflow usa el backend:

```text
m4-c1/<student_identity>/rds.tfstate
```

El plan debe incluir, como mínimo:

- `aws_db_subnet_group.rds`;
- `aws_security_group.rds`;
- `aws_security_group.backend_b_source`;
- dos `aws_network_interface_sg_attachment.backend_b_source`;
- `aws_vpc_security_group_egress_rule.backend_to_rds`;
- `aws_db_parameter_group.postgres`;
- `aws_db_instance.rds`;
- dos policies inline `rds-secret-read-only`.

Resultado esperado de `apply`:

```text
Apply complete! Resources: 10 added, 0 changed, 0 destroyed.
```

La cantidad puede variar si Terraform agrega dependencias internas, pero no debe destruir la VPC, las EC2 ni los buckets de LAB02.

---

## 8. Verificar RDS y la red

Desde los outputs del workflow anotá:

- `rds_identifier`;
- `rds_endpoint`;
- `rds_port`;
- `rds_secret_arn`;
- `rds_security_group_id`;
- `backend_security_group_id`.

En AWS Console revisá:

### RDS

- estado `Available`;
- motor PostgreSQL;
- `Publicly accessible = No`;
- subnet group con las dos subnets `db`;
- Security Group `SG-RDS` asociado;
- storage encryption habilitado;
- backup retention de un día;
- deletion protection deshabilitada solo para permitir cleanup del laboratorio.

### Security Groups

En el inbound de `SG-RDS` debe existir únicamente:

```text
TCP 5432
Source: SG-BACKEND-B-RDS-SOURCE
```

No debe existir:

```text
0.0.0.0/0
CIDR de toda la VPC
IP fija de una EC2
```

En el outbound de `SG-BACKEND` debe existir una regla TCP 5432 con destino lógico `SG-RDS`. El SG fuente de backend-b debe estar asociado solo a las dos ENI de backend-b. No agregues una regla amplia a todo Internet para resolver un error.

### Secrets Manager

Abrí el secreto creado por RDS y verificá solo sus metadatos:

- pertenece a RDS;
- está en la región correcta;
- el ARN coincide con el output;
- no copies ni publiques su valor.

---

## 9. Preparar los scripts en una EC2

Los scripts del repositorio son:

```text
labs/m4-c1-lab/scripts/inicializar-rds.sh
labs/m4-c1-lab/scripts/validar-rds.sh
```

Desde una sesión de Session Manager en cada EC2, descargalos desde la branch `main` del repositorio del curso y hacelos ejecutables. Reemplazá la URL si trabajás con un fork:

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

No guardes el ARN junto con passwords en archivos permanentes. Usá variables de sesión:

```bash
export RDS_ENDPOINT="<rds_endpoint>"
export RDS_SECRET_ARN="<rds_secret_arn>"
export AWS_REGION="us-east-1"
```

---

## 10. Inicializar el dato de prueba

Abrí Session Manager sobre `backend-b-01` y ejecutá:

```bash
sudo /opt/security-lab/inicializar-rds.sh "$RDS_ENDPOINT" 5432 "$RDS_SECRET_ARN"
```

Resultado esperado:

```text
Inicializando tabla lab_access con conexión TLS. La contraseña no se imprime.
CREATE TABLE
INSERT 0 1
Inicialización completada.
```

El script crea o actualiza:

```sql
lab_access(id integer primary key, mensaje text not null)
```

No se imprime el contenido del secreto ni la password.

---

## 11. Ejecutar la matriz de pruebas

Ejecutá el mismo comando desde cada instancia:

```bash
sudo /opt/security-lab/validar-rds.sh "$RDS_ENDPOINT" 5432 "$RDS_SECRET_ARN"
```

Resultados esperados:

| Instancia | TCP 5432 | Secreto | SQL |
|---|---|---|---|
| `backend-a-01` | bloqueado/timeout | no se intenta | no aplica |
| `backend-a-02` | bloqueado/timeout | no se intenta | no aplica |
| `backend-b-01` | `TCP_REACHABLE` | permitido | fila visible |
| `backend-b-02` | `TCP_REACHABLE` | permitido | fila visible |

En backend-b debe aparecer:

```text
TCP_REACHABLE
SECRET_RETRIEVED_WITHOUT_PRINTING_PASSWORD
1|dato de prueba del laboratorio
```

La conexión utiliza `sslmode=require`. Si se prueba con `sslmode=disable`, PostgreSQL debe rechazar la conexión por `rds.force_ssl`.

La secuencia de interpretación es importante:

1. si TCP está bloqueado, el problema está en Security Groups, rutas o endpoint;
2. si TCP llega pero el secreto falla, el problema está en IAM;
3. si el secreto funciona pero SQL falla, revisá credenciales, base, tabla o TLS.

---

## 12. Checkpoints

Respondé antes de avanzar:

1. ¿Por qué `backend-a` queda bloqueado antes de intentar autenticarse?
2. ¿Por qué el origen del inbound es un Security Group y no una IP?
3. ¿Qué diferencia hay entre el SG backend y el role IAM de una EC2?
4. ¿Por qué RDS no necesita IP pública para que backend-b lo alcance?
5. ¿Qué evidencia demuestra que la password no está en Terraform?
6. ¿Qué evidencia demuestra que la conexión usa TLS?
7. ¿Qué permiso permite recuperar el secreto?
8. ¿Qué riesgo quedaría si el secreto se pudiera leer desde backend-a?
9. ¿Qué significa que `multi_az = false` en este ejercicio?
10. ¿Qué dato deberías ocultar al compartir la evidencia?

---

## 13. Troubleshooting

| Síntoma | Posible causa | Revisión |
|---|---|---|
| El workflow falla al leer VPC | `student_identity` no coincide con LAB02 | comparar tags y Environment `lab` |
| RDS queda en `creating` | creación normal o subnet/SG incompletos | esperar y revisar eventos de RDS |
| Backend-b tiene timeout | falta egress 5432 o inbound de SG-RDS | revisar ambos SG, no abrir `0.0.0.0/0` |
| Backend-a llega a TCP | SG-RDS tiene origen incorrecto | dejar solo SG backend como origen |
| `GetSecretValue AccessDenied` en backend-b | policy inline ausente o ARN incorrecto | revisar role, policy y output del secreto |
| Backend-a puede leer el secreto | policy adjuntada al role equivocado | quitarla y conservarla solo en backend-b |
| `psql` no existe | foundation no fue actualizado | repetir apply fundacional y esperar SSM |
| SQL rechaza conexión sin TLS | comportamiento esperado | usar `sslmode=require` |
| Terraform quiere destruir VPC/EC2 | se está usando el root equivocado | detenerse y ejecutar solo `terraform-rds` |

---

## 14. Limpieza obligatoria

Primero destruí RDS desde el workflow **M4-C1 RDS Network Security**:

1. ejecutá el workflow con `action = destroy`;
2. revisá que afecte solo RDS, SG-RDS, subnet group, parameter group, regla egress y policies de secreto;
3. ejecutá `destroy`;
4. esperá el resultado exitoso.

Después verificá que no queden:

- instancia RDS;
- DB subnet group;
- parameter group personalizado;
- SG-RDS y el SG fuente dedicado de backend-b;
- regla backend→RDS;
- policies inline `rds-secret-read-only`;
- secreto administrado por RDS.

No destruyas la fundación hasta completar la clase si LAB02 se reutiliza. Si finaliza el ciclo completo del módulo, ejecutá luego `destroy` en **M4-C1 Infra Deploy** y verificá VPC, EC2, buckets y roles.

No elimines el OIDC Provider compartido ni el role de despliegue sin autorización.

---

## 15. Entregables

1. Link del run `plan` de RDS.
2. Link del run `apply` de RDS.
3. Outputs sin valores sensibles.
4. Diagrama con subnets db, `SG-BACKEND`, SG fuente de backend-b, `SG-RDS` y RDS.
5. Tabla de reglas de Security Groups.
6. Evidencia de RDS privado y cifrado.
7. Evidencia de Secrets Manager sin mostrar el valor secreto.
8. Salida de `validar-rds.sh` en las cuatro EC2.
9. Evidencia de `TCP_REACHABLE` solo en backend-b.
10. Evidencia de la fila SQL desde backend-b.
11. Evidencia de cleanup del root RDS.
12. Respuestas de los checkpoints.

No entregues passwords, tokens, valores de secretos, access keys, archivos `.tfstate`, planes Terraform ni datos personales.

---

## 16. Criterios de evaluación

| Criterio | Evidencia | Ponderación |
|---|---|---:|
| RDS privado | subnet group db, `publicly_accessible = false`, cifrado | 20% |
| Seguridad de red | SG-RDS solo desde SG backend y egress 5432 explícito | 25% |
| IAM y secretos | GetSecretValue solo en backend-b, sin passwords versionadas | 20% |
| TLS y SQL | conexión `sslmode=require` y lectura de tabla | 15% |
| Pruebas negativas | backend-a bloqueado y permisos interpretados | 10% |
| Cleanup | destroy y verificación de recursos sensibles | 10% |

Errores críticos:

- permitir RDS desde `0.0.0.0/0`;
- publicar o guardar la password del RDS;
- asignar `GetSecretValue` a backend-a;
- abrir SSH público como solución;
- ejecutar el destroy del root fundacional antes del root RDS;
- afirmar que RDS es Multi-AZ cuando este ejercicio usa `multi_az = false`.

---

## 17. Cierre

Completá la frase:

> `backend-a` no puede consultar RDS porque __________. `backend-b` llega a RDS porque __________. La red no reemplaza IAM porque __________. El secreto no se guarda en Terraform porque __________. TLS aporta __________. Una mejora para producción sería __________.
