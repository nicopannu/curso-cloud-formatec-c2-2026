# LAB02 — EC2 privadas, red, S3 y permisos IAM

**Curso:** Arquitectura e Ingeniería Cloud | C2 — FormaTEC 2026  
**Duración estimada:** 120 minutos  
**Modalidad:** individual o en parejas  
**Región de referencia:** `us-east-1`  
**Tema:** redes privadas, NAT, Systems Manager, S3 e IAM

---

## 1. Contexto

En LAB01 configuraste GitHub Actions para autenticarse en AWS mediante OIDC y credenciales temporales.

En este laboratorio vas a desplegar una arquitectura base con Terraform y luego vas a revisar cómo los permisos IAM modifican lo que cada instancia puede hacer sobre Amazon S3.

El laboratorio separa dos decisiones:

1. **Conectividad:** las EC2 no tienen IP pública. Para acceder a servicios AWS utilizan rutas privadas, una NAT instance y un Gateway Endpoint para S3.
2. **Autorización:** la conectividad no decide qué puede hacer cada instancia. Esa decisión pertenece al role IAM y a sus policies.

No confundas estas preguntas:

- ¿La instancia puede llegar al servicio?
- ¿El role de la instancia tiene permiso para realizar la acción?

Una respuesta positiva a la primera no implica una respuesta positiva a la segunda.

---

## 2. Arquitectura objetivo

```text
                                  Internet
                                      │
                              Internet Gateway
                                      │
                         ┌────────────┴────────────┐
                         │                         │
                   Public subnet              Public subnet
                         │                         │
                  NAT instance              reservado
                         │
              ┌──────────┴──────────┐
              │                     │
       Backend subnets       Backend subnets
       backend-a, AZ1/AZ2    backend-b, AZ1/AZ2
              │                     │
       2 EC2 privadas        2 EC2 privadas
              │                     │
              └──────────┬──────────┘
                         │
                 Gateway Endpoint S3
                         │
                    Amazon S3
              bucket-a / bucket-b

       DB subnets AZ1/AZ2: reservadas para el siguiente laboratorio
```

### Componentes y responsabilidad

| Componente | Responsabilidad |
|---|---|
| VPC `10.41.0.0/16` | límite de red del laboratorio |
| Subnets públicas | NAT instance e Internet Gateway |
| Subnets `backend-a` | dos EC2 privadas del grupo A |
| Subnets `backend-b` | dos EC2 privadas del grupo B |
| Subnets `db` | segmento reservado sin salida por defecto |
| NAT instance | salida HTTPS de las subnets backend hacia Internet |
| Gateway Endpoint S3 | acceso privado a S3 sin pasar por Internet |
| Security Groups | control de tráfico de las instancias |
| EC2 | ejecución de comandos y prueba de permisos |
| IAM role | identidad de cada instancia |
| S3 | almacenamiento de los archivos de prueba |
| Systems Manager | acceso administrativo sin SSH ni IP pública |

---

## 3. Pre-requisitos

Antes de comenzar, verificá:

- LAB01 completado.
- El repositorio contiene el workflow de M4-C1.
- El environment `lab` existe.
- `AWS_ROLE_ARN` apunta al role OIDC correcto.
- `AWS_REGION` tiene el valor `us-east-1`.
- `STUDENT_IDENTITY` existe y conserva el valor usado en LAB01.
- Tenés acceso para adjuntar al role OIDC la policy de despliegue incluida en este lab.
- Tenés autorización para ejecutar `apply` en la cuenta de laboratorio.

El workflow utiliza estas variables del environment `lab`:

| Variable | Uso |
|---|---|
| `AWS_ROLE_ARN` | role que GitHub Actions asume mediante OIDC |
| `AWS_REGION` | región de despliegue |
| `STUDENT_IDENTITY` | nombres y tags de los recursos |
| `TF_STATE_BUCKET` | bucket S3 para el state remoto |

Terraform crea automáticamente un role y un instance profile por cada EC2. No se necesita `EC2_INSTANCE_PROFILE_NAME`. Cada role recibe inicialmente `AmazonSSMManagedInstanceCore` y `s3-lab02-full-buckets`, limitada a los dos buckets del laboratorio.
No agregues access keys permanentes:

```text
AWS_ACCESS_KEY_ID
AWS_SECRET_ACCESS_KEY
```

---

## 4. Revisar el código antes de desplegar

Desde la raíz del repositorio, abrí:

```text
labs/m4-c1-lab/README.md
labs/m4-c1-lab/terraform/providers.tf
labs/m4-c1-lab/terraform/network.tf
labs/m4-c1-lab/terraform/ec2.tf
labs/m4-c1-lab/terraform/iam.tf
labs/m4-c1-lab/terraform/s3.tf
labs/m4-c1-lab/terraform/outputs.tf
labs/m4-c1-lab/policies/terraform-deploy-policy.json
.github/workflows/m4-c1-infra-deploy.yml
```

Identificá antes de ejecutar:

- dónde se define la VPC;
- qué subnets reciben ruta por defecto;
- qué subnets no reciben ruta por defecto;
- qué recurso actúa como NAT;
- qué route tables reciben el endpoint de S3;
- qué instancias tienen IP pública;
- qué permisos se dejan para la etapa visual de IAM.

Ejecutá las validaciones locales:

```bash
terraform -chdir=labs/m4-c1-lab/terraform fmt -check -recursive
terraform -chdir=labs/m4-c1-lab/terraform init -backend=false
terraform -chdir=labs/m4-c1-lab/terraform validate
bash -n labs/m4-c1-lab/scripts/popular-s3-desde-local.sh
bash labs/m4-c1-lab/scripts/validar-estructura.sh
```

### Resultado esperado

Todas las validaciones terminan sin errores. `terraform init -backend=false` se usa para la validación local; el workflow de GitHub Actions inicializa el state remoto.

---

## 4.1 Habilitar el role OIDC para desplegar con Terraform

LAB01 dejó el role OIDC con permiso para verificar la identidad temporal. Antes de ejecutar Terraform, agregale la policy de despliegue entregada con LAB02:

```text
labs/m4-c1-lab/policies/terraform-deploy-policy.json
```

Desde AWS Console:

1. Abrí **IAM → Policies → Create policy**.
2. Elegí el editor **JSON**.
3. Copiá el contenido completo de `terraform-deploy-policy.json`.
4. Continuá con **Next** y asignale el nombre `formatec-terraform-deploy`.
5. Creá la policy.
6. Abrí **IAM → Roles** y seleccioná el role OIDC creado en LAB01.
7. Elegí **Add permissions → Attach policies**.
8. Buscá `formatec-terraform-deploy` y adjuntala.

La policy está agrupada por servicio:

| Grupo | Uso en LAB02 |
|---|---|
| `STSIdentity` | comprobar la identidad temporal asumida por GitHub Actions |
| `S3TerraformManagement` | operar el backend remoto y crear o destruir los buckets del lab |
| `EC2TerraformManagement` | administrar VPC, subnets, rutas, endpoints, Security Groups y EC2 |
| `IAMReadForTerraform` | leer roles, policies e instance profiles durante `plan` y refresh |
| `IAMRolesForTerraform` | crear los roles de EC2, policies inline y asociaciones necesarias |
| `IAMPassRoleToWorkloads` | entregar roles únicamente a EC2, Lambda o ECS Tasks |
| `IAMInstanceProfilesForTerraform` | crear y asociar instance profiles a las EC2 |
| `IAMManagedPoliciesForTerraform` | permitir que otros labs creen policies administradas reutilizando el mismo artefacto |

Todos los statements usan `Resource: "*"`. Esto evita hardcodear un account ID o un nombre de alumno y permite reutilizar la policy en otros labs que usen los mismos servicios. A cambio, el alcance es más amplio que el de una policy de producción: utilizala únicamente en la cuenta educativa y no la adjuntes a roles runtime de EC2.

### Resultado esperado

El role OIDC conserva su trust policy restringida al repositorio y environment correctos, y ahora muestra `formatec-terraform-deploy` en la pestaña **Permissions**. No agregues `AdministratorAccess` ni access keys permanentes.

---

## 5. Ejecutar `plan` desde GitHub Actions

1. Abrí el repositorio en GitHub.
2. Elegí **Actions**.
3. Abrí **M4-C1 Infra Deploy**.
4. Elegí **Run workflow**.
5. Seleccioná la rama de trabajo.
6. En `action`, elegí `plan`.
7. Ejecutá el workflow.

Revisá estos pasos del job:

```text
1 · Terraform fmt
2 · Terraform init with remote state
3 · Terraform validate
4 · Terraform plan
```

El init remoto utiliza una key separada por identidad:

```text
m4-c1/<student_identity>/foundation.tfstate
```

### Resultado esperado

El plan no muestra cambios destructivos inesperados. Para una cuenta sin esta implementación, esperá recursos nuevos de red, EC2 y S3.

Antes de continuar, respondé:

- ¿Qué recursos son públicos?
- ¿Qué recursos son privados?
- ¿Qué recurso permite que una EC2 privada salga hacia Internet?
- ¿Por qué S3 tiene además un endpoint?
- ¿Qué recurso queda fuera del despliegue porque pertenece al siguiente laboratorio?

---

## 6. Ejecutar `apply` y observar el despliegue

Ejecutá nuevamente **Run workflow**, esta vez con:

```text
action = apply
```

Esperá que finalicen:

```text
Terraform fmt
Terraform init with remote state
Terraform validate
Terraform plan
Terraform plan for apply
Terraform apply
```

No avances si `Terraform apply` muestra un error. Leé primero el recurso que falló y comparalo con la arquitectura.

### Resultado esperado

El workflow termina correctamente y crea:

- 1 VPC;
- 2 subnets públicas;
- 4 subnets privadas backend;
- 2 subnets privadas db;
- 1 NAT instance;
- 4 EC2 backend privadas;
- 4 roles IAM, uno por EC2;
- 4 instance profiles individuales;
- `AmazonSSMManagedInstanceCore` en cada role;
- `s3-lab02-full-buckets` limitada a los dos buckets en cada role;
- 1 Gateway Endpoint para S3;
- 2 buckets privados.

Las instancias backend no deben tener IP pública.

---

## 7. Verificar la arquitectura desde AWS Console

Abrí **AWS Console → us-east-1** y verificá los recursos usando el `student_identity` de tus tags.

### 7.1 VPC y subnets

En **VPC → Your VPCs** verificá:

- CIDR `10.41.0.0/16`;
- DNS hostnames habilitado;
- DNS resolution habilitado.

En **VPC → Subnets** verificá:

- dos subnets con `Tier = public`;
- dos subnets con `Tier = backend-a`;
- dos subnets con `Tier = backend-b`;
- dos subnets con `Tier = db`;
- solo las públicas tienen `Map public IPv4 address on launch` habilitado.

### 7.2 Route tables

En **VPC → Route tables**, revisá:

- públicas → `0.0.0.0/0` hacia Internet Gateway;
- backend → `0.0.0.0/0` hacia la interfaz de la NAT instance;
- backend → ruta administrada por el Gateway Endpoint de S3;
- db → únicamente la ruta local de la VPC.

La ausencia de ruta por defecto en `db` es una decisión de segmentación, no un error.

### 7.3 EC2

En **EC2 → Instances** verificá:

- cuatro instancias backend en estado `running`;
- ninguna tiene IP pública;
- las instancias están distribuidas en dos zonas de disponibilidad;
- todas usan el instance profile configurado para Systems Manager;
- la NAT instance es la única EC2 con IP pública.

### Resultado esperado

La arquitectura observada coincide con el diagrama y no hay una EC2 backend expuesta directamente a Internet.

---

## 8. Verificar Systems Manager

Abrí **AWS Console → Systems Manager → Fleet Manager → Managed nodes**.

Esperá a que las cuatro EC2 backend aparezcan como nodos administrados. El estado esperado es:

```text
Ping status: Online
```

Si no aparecen, revisá:

- el instance profile;
- la policy `AmazonSSMManagedInstanceCore`;
- la salida HTTPS desde la subnet privada;
- la ruta hacia la NAT instance;
- la resolución DNS de la VPC;
- el estado del agente SSM.

No uses SSH ni agregues una IP pública para resolver este punto.

Abrí una sesión desde **Systems Manager → Session Manager → Start session** contra:

```text
backend-a-01
```

Dentro de la sesión verificá:

```bash
hostname
ip route
curl -I https://ssm.us-east-1.amazonaws.com
aws sts get-caller-identity
```

La identidad devuelta por `aws sts get-caller-identity` debe corresponder al role asociado a la instancia, no a una access key guardada en el sistema.

---

## 9. Popular S3 desde local o Dev Container

La carga inicial se realiza desde tu máquina local o desde el Dev Container. No crees archivos de prueba ni ejecutes `aws s3 sync` desde una EC2.

Desde la raíz del repositorio, con una identidad AWS autorizada para escribir temporalmente en ambos buckets, ejecutá:

```bash
aws sts get-caller-identity --region us-east-1
./labs/m4-c1-lab/scripts/popular-s3-desde-local.sh <account-number> <student-id>
```

Ejemplo:

```bash
./labs/m4-c1-lab/scripts/popular-s3-desde-local.sh 123456789012 perez-ana
```

El script calcula los nombres de `bucket-a` y `bucket-b`, verifica que existan y carga estos objetos en ambos:

```text
folder-a/a.txt
folder-b/b.txt
shared/shared.txt
```

Los archivos se generan en un directorio temporal local, se sincronizan con `aws s3 sync` y se eliminan al finalizar. El script no crea recursos AWS, no modifica policies y no usa `--delete`.

### Resultado esperado

La salida muestra la carga de tres objetos en cada bucket y luego los lista para verificación. Conservá los nombres de los buckets para las pruebas de permisos.

Las EC2 se utilizarán desde este punto únicamente para abrir sesiones de Session Manager y ejecutar comandos de lectura, escritura o borrado según el role IAM asignado.

---

## 10. Revisar la policy amplia inicial

Desde **AWS Console → IAM → Roles**, ubicá el role utilizado por las EC2 del laboratorio.

Revisá su policy inicial y anotá:

- qué acciones permite;
- sobre qué buckets actúa;
- por qué esa policy permite completar la carga inicial;
- qué riesgo tendría dejarla instalada.

No cambies todavía la policy hasta registrar la situación inicial.

---

## 11. Reemplazar la policy desde IAM Console

Creá o editá las policies desde la consola de IAM. Usá los nombres reales de los buckets obtenidos en Terraform.

### 11.1 `backend-a-01`

Debe tener control total sobre el bucket A y acceso denegado al bucket B.

Bucket A:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "BucketAFullAccess",
      "Effect": "Allow",
      "Action": "s3:*",
      "Resource": [
        "arn:aws:s3:::<bucket-a>",
        "arn:aws:s3:::<bucket-a>/*"
      ]
    }
  ]
}
```

No agregues un `Allow` para el bucket B.

### 11.2 `backend-a-02`

Debe listar el bucket A y leer sus objetos:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "ListBucketA",
      "Effect": "Allow",
      "Action": "s3:ListBucket",
      "Resource": "arn:aws:s3:::<bucket-a>"
    },
    {
      "Sid": "ReadBucketA",
      "Effect": "Allow",
      "Action": "s3:GetObject",
      "Resource": "arn:aws:s3:::<bucket-a>/*"
    }
  ]
}
```

### 11.3 `backend-b-01`

Debe tener control total sobre el bucket B y leer únicamente `shared/` del bucket A.

Usá dos statements separados:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "BucketBFullAccess",
      "Effect": "Allow",
      "Action": "s3:*",
      "Resource": [
        "arn:aws:s3:::<bucket-b>",
        "arn:aws:s3:::<bucket-b>/*"
      ]
    },
    {
      "Sid": "ReadSharedFromBucketA",
      "Effect": "Allow",
      "Action": "s3:GetObject",
      "Resource": "arn:aws:s3:::<bucket-a>/shared/*"
    },
    {
      "Sid": "ListSharedFromBucketA",
      "Effect": "Allow",
      "Action": "s3:ListBucket",
      "Resource": "arn:aws:s3:::<bucket-a>",
      "Condition": {
        "StringLike": {
          "s3:prefix": ["shared", "shared/*"]
        }
      }
    }
  ]
}
```

### 11.4 `backend-b-02`

Debe leer el bucket B completo, pero escribir y borrar únicamente en `folder-b/`.

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "ListBucketB",
      "Effect": "Allow",
      "Action": "s3:ListBucket",
      "Resource": "arn:aws:s3:::<bucket-b>"
    },
    {
      "Sid": "ReadBucketB",
      "Effect": "Allow",
      "Action": "s3:GetObject",
      "Resource": "arn:aws:s3:::<bucket-b>/*"
    },
    {
      "Sid": "WriteAndDeleteFolderB",
      "Effect": "Allow",
      "Action": ["s3:PutObject", "s3:DeleteObject"],
      "Resource": "arn:aws:s3:::<bucket-b>/folder-b/*"
    }
  ]
}
```

No agregues `s3:*` sobre ambos buckets para resolver errores de permisos.

---

## 12. Probar permisos desde cada EC2

Abrí una sesión de Session Manager para cada instancia y ejecutá las pruebas correspondientes.

Usá estas variables dentro de cada sesión:

```bash
BUCKET_A=<bucket-a>
BUCKET_B=<bucket-b>
```

### `backend-a-01`

Permitido:

```bash
aws s3 ls "s3://${BUCKET_A}"
aws s3 cp "s3://${BUCKET_A}/folder-a/a.txt" /tmp/a.txt
aws s3api put-object --bucket "$BUCKET_A" --key "validation/a-01.txt" --body /dev/null
aws s3api delete-object --bucket "$BUCKET_A" --key "validation/a-01.txt"
```

El `put-object` usa `/dev/null` como body efímero: comprueba escritura sin crear un archivo de trabajo ni cargar la data del ejercicio desde la EC2.

Debe fallar con `AccessDenied`:

```bash
aws s3 ls "s3://${BUCKET_B}"
```

### `backend-a-02`

Permitido:

```bash
aws s3 ls "s3://${BUCKET_A}"
aws s3 cp "s3://${BUCKET_A}/folder-a/a.txt" /tmp/a.txt
```

Debe fallar:

```bash
aws s3api put-object --bucket "$BUCKET_A" --key "validation/a-02.txt" --body /dev/null
aws s3 ls "s3://${BUCKET_B}"
```

### `backend-b-01`

Permitido:

```bash
aws s3 ls "s3://${BUCKET_B}"
aws s3 cp "s3://${BUCKET_A}/shared/shared.txt" /tmp/shared.txt
aws s3api put-object --bucket "$BUCKET_B" --key "validation/b-01.txt" --body /dev/null
aws s3api delete-object --bucket "$BUCKET_B" --key "validation/b-01.txt"
```

Debe fallar el acceso a otra carpeta del bucket A:

```bash
aws s3 cp "s3://${BUCKET_A}/folder-a/a.txt" /tmp/a.txt
```

### `backend-b-02`

Permitido:

```bash
aws s3 ls "s3://${BUCKET_B}"
aws s3 cp "s3://${BUCKET_B}/folder-a/a.txt" /tmp/a.txt
aws s3api put-object --bucket "$BUCKET_B" --key "folder-b/validation-b-02.txt" --body /dev/null
aws s3api delete-object --bucket "$BUCKET_B" --key "folder-b/validation-b-02.txt"
```

Debe fallar la escritura fuera de `folder-b/`:

```bash
aws s3api put-object --bucket "$BUCKET_B" --key "shared/validation-b-02.txt" --body /dev/null
```

Registrá para cada prueba:

| Instancia | Acción | Resultado esperado | Resultado observado |
|---|---|---|---|
| `backend-a-01` | leer/escribir/borrar A | permitido | |
| `backend-a-01` | listar B | denegado | |
| `backend-a-02` | listar/leer A | permitido | |
| `backend-a-02` | escribir A | denegado | |
| `backend-b-01` | controlar B | permitido | |
| `backend-b-01` | leer `shared/` de A | permitido | |
| `backend-b-01` | leer `folder-a/` de A | denegado | |
| `backend-b-02` | leer B | permitido | |
| `backend-b-02` | escribir/borrar `folder-b/` | permitido | |
| `backend-b-02` | escribir `shared/` de B | denegado | |

Un `AccessDenied` esperado es evidencia de que la policy está funcionando, no un error del laboratorio.

---

## 13. Troubleshooting

| Problema | Qué revisar |
|---|---|
| Las EC2 no aparecen en SSM | instance profile, `AmazonSSMManagedInstanceCore`, DNS, ruta privada, NAT y agente |
| `curl` hacia SSM expira | ruta hacia NAT, forwarding, masquerade y Security Group |
| `aws s3 ls` expira | Gateway Endpoint, route table de la subnet y DNS |
| S3 responde `AccessDenied` | role activo, policy, ARN del bucket y ARN del objeto |
| `ListBucket` funciona pero `GetObject` falla | faltan permisos sobre `bucket/*` |
| `GetObject` funciona pero listar una carpeta falla | falta `s3:ListBucket` o la condición `s3:prefix` |
| `backend-b-02` escribe fuera de `folder-b` | la policy usa un recurso demasiado amplio |
| Terraform propone reemplazar todas las EC2 | revisá cambios en `user_data`, identidad, AMI y variables antes de aplicar |

No resuelvas un `AccessDenied` agregando `AdministratorAccess`.

---

## 14. Limpieza

Cuando termines las pruebas, ejecutá el workflow con:

```text
action = destroy
```

El destroy debe usar el mismo `TF_STATE_BUCKET`, `student_identity` y key remota que el apply.

Verificá después:

- no quedan VPC del laboratorio;
- no quedan EC2 activas;
- no quedan NAT instances;
- no quedan endpoints S3;
- no quedan buckets ni objetos de prueba;
- el state remoto fue eliminado según la política definida para el curso.

No borres el OIDC Provider, el role OIDC ni el environment `lab` si pertenecen a LAB01 o a otros laboratorios del curso.

---

## 15. Entregables

Entregá:

1. Archivo `policies/terraform-deploy-policy.json` conservado sin account IDs ni nombres de alumno hardcodeados.
2. Captura de `formatec-terraform-deploy` adjunta al role OIDC utilizado por GitHub Actions.
3. Captura o enlace del run `plan` exitoso.
4. Captura o enlace del run `apply` exitoso.
5. Diagrama de la arquitectura con VPC, subnets públicas/privadas, NAT, endpoint S3 y EC2.
6. Tabla de rutas indicando el next hop de cada segmento.
7. Tabla de permisos con acciones permitidas y denegadas por instancia.
8. Evidencia de una sesión de Systems Manager.
9. Evidencia de al menos tres operaciones S3 permitidas.
10. Evidencia de al menos tres operaciones S3 rechazadas con `AccessDenied`.
11. Captura o enlace del run `destroy` exitoso.
12. Respuestas breves:
    - ¿Por qué una EC2 privada necesita una ruta hacia la NAT para llegar a SSM?
    - ¿Por qué S3 utiliza además un Gateway Endpoint?
    - ¿Qué diferencia hay entre el ARN del bucket y el ARN de sus objetos?
    - ¿Por qué `s3:ListBucket` se aplica al bucket y `s3:GetObject` a `bucket/*`?
    - ¿Qué riesgo se evita al reemplazar la policy amplia inicial?
