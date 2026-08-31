# M4-C1: Seguridad de acceso a S3 desde EC2 privadas

Este laboratorio crea una base de red, EC2 privadas y dos buckets S3 para practicar permisos IAM por rol desde la consola de AWS.

La continuidad con AWS se hace con GitHub Actions OIDC. No uses secretos `AWS_ACCESS_KEY_ID` ni `AWS_SECRET_ACCESS_KEY`. El ambiente `lab` de GitHub Actions ya existe y entrega estas variables:

- `AWS_ROLE_ARN`
- `AWS_REGION`
- `STUDENT_IDENTITY`
- `TF_STATE_BUCKET`

Terraform usa `STUDENT_IDENTITY` como `var.student_identity` para nombrar y etiquetar recursos. Todos los recursos llevan las etiquetas `StudentIdentity`, `Lab=m4-c1` y `ManagedBy=terraform`.

## Overview del laboratorio

M4-C1 se desarrolla en dos guías relacionadas:

| Guía | Tema | Resultado |
|---|---|---|
| [LAB01 — OIDC desde AWS Console](guias/guia-seguridad-lab01-oidc.md) | GitHub Actions, OIDC, IAM y credenciales temporales | GitHub Actions puede asumir un role AWS sin access keys permanentes |
| [LAB02 — EC2 privadas, red, S3 y permisos IAM](guias/guia-seguridad-lab02-ec2-red-s3.md) | VPC, subnets, NAT, SSM, S3 y mínimo privilegio | cuatro EC2 privadas acceden a S3 según su role IAM |
| [LAB03 — RDS privado y segmentación de red](guias/guia-seguridad-lab03-rds-segmentacion.md) | Security Groups, RDS PostgreSQL, Secrets Manager y TLS | solo backend-b alcanza y consulta RDS |

LAB01 se completa primero porque deja preparados el OIDC Provider, el role de GitHub Actions, el environment `lab` y `STUDENT_IDENTITY`. LAB02 utiliza esa continuidad para desplegar la infraestructura y observar la diferencia entre conectividad de red y autorización IAM.

LAB03 reutiliza la infraestructura de LAB02 y se administra con un workflow separado. Su state remoto usa otra key para que el destroy de RDS no destruya la VPC, las EC2 ni los buckets fundacionales.

La infraestructura de LAB02 se administra con Terraform. Los permisos de acceso de las EC2 a S3 se revisan y ajustan manualmente desde IAM Console para que la relación entre identidad, acción y recurso quede visible durante el ejercicio.

## Arquitectura resumida

```text
Internet
   │
Internet Gateway
   │
subnet pública ── NAT instance ── route tables backend
                                      │
                 ┌────────────────────┼────────────────────┐
                 │                    │                    │
          backend-a AZ1        backend-a AZ2        Gateway Endpoint S3
          EC2 privada          EC2 privada                 │
                 │                    │              bucket-a / bucket-b
                 └────────────────────┼────────────────────┘
                                      │
                 ┌────────────────────┼────────────────────┐
                 │                    │                    │
          backend-b AZ1        backend-b AZ2          subnets db
          EC2 privada          EC2 privada             reservadas

Las EC2 backend no tienen IP pública. SSM usa el role de la instancia y la
salida HTTPS; S3 utiliza el Gateway Endpoint asociado a las route tables backend.
```

### Responsabilidad de cada capa

| Capa | Componentes | Decisión que se observa |
|---|---|---|
| Red | VPC `10.41.0.0/16`, subnets públicas/privadas | separar exposición pública, aplicaciones y base de datos |
| Salida | NAT instance, route tables, forwarding | permitir salida de backend sin IP pública |
| Acceso AWS | Gateway Endpoint para S3 | llegar a S3 por la red de AWS sin depender de Internet |
| Cómputo | cuatro EC2 Amazon Linux privadas | representar grupos backend con identidades diferentes |
| Administración | Systems Manager Session Manager | administrar sin SSH ni bastion host |
| Almacenamiento | dos buckets S3 privados | comparar permisos por bucket y por prefijo |
| Identidad | roles IAM y policies | aplicar mínimo privilegio por instancia |
| Automatización | GitHub Actions + OIDC + Terraform | desplegar sin credenciales permanentes |

La conectividad y los permisos se validan por separado. Que una EC2 pueda resolver y alcanzar S3 no significa que su role pueda listar, leer, escribir o borrar objetos.

## Workflows del laboratorio

El repositorio separa la validación de identidad del despliegue de infraestructura:

| Workflow | Propósito | Crea recursos |
|---|---|---|
| `M4-C1 OIDC Verify` | comprobar que GitHub Actions asume el role AWS mediante OIDC y mostrar `sts:GetCallerIdentity` | No |
| `M4-C1 Infra Deploy` | ejecutar `plan`, `apply` o `destroy` sobre Terraform | Sí, cuando se elige `apply` |
| `M4-C1 RDS Network Security` | desplegar, probar y destruir RDS y sus reglas de red | Sí, cuando se elige `apply` |

`M4-C1 Infra Deploy` también utiliza OIDC antes de ejecutar Terraform. La autenticación no se realiza con access keys guardadas en GitHub.

Para completar LAB01, ejecutá primero `M4-C1 OIDC Verify` con `workflow_dispatch`. Para LAB02, ejecutá `M4-C1 Infra Deploy` con `plan`, revisá el resultado y luego `apply`.

Para LAB03, completá LAB02 y ejecutá `M4-C1 RDS Network Security`. No uses `M4-C1 Infra Deploy` para administrar el RDS.

## Que Crea Terraform

- Una VPC con DNS habilitado.
- Dos subnets publicas en dos Availability Zones.
- Dos subnets privadas `backend-a`, dos subnets privadas `backend-b` y dos subnets privadas `db`.
- Un Internet Gateway.
- Una instancia NAT `t3.micro` en subnet publica, con IP publica y `source_dest_check=false`.
- Tablas de ruta privadas de aplicaciones con salida por la interfaz de red de la NAT instance.
- Tablas de ruta privadas de base de datos sin ruta default a Internet ni NAT.
- Un VPC endpoint Gateway para S3 asociado solo a las route tables de aplicaciones.
- Dos buckets S3 privados, versionados, cifrados, con bloqueo de acceso publico y `force_destroy=true`.
- Cuatro EC2 Amazon Linux privadas: `backend-a-01`, `backend-a-02`, `backend-b-01`, `backend-b-02`.
- Cuatro roles IAM, uno por EC2, cada uno con su instance profile.
- `AmazonSSMManagedInstanceCore` asociado a cada role para Session Manager.
- Policy inline inicial `s3-lab02-full-buckets` en cada role, limitada a los dos buckets del laboratorio.

Terraform no crea RDS, ALB, endpoints publicos de aplicacion, CloudFront, HTTPS, SSH keys ni objetos S3. Terraform crea los roles IAM de las EC2 porque LAB02 comienza con acceso amplio y luego lo reemplaza por policies segmentadas desde IAM Console.

El root separado `terraform-rds/` agrega RDS PostgreSQL privado, DB subnet group, `SG-RDS`, regla egress backend→RDS, parameter group TLS y policies `rds-secret-read-only` para backend-b.

## Antes de Empezar

LAB02 incluye una policy de despliegue reutilizable para el role OIDC:

```text
labs/m4-c1-lab/policies/terraform-deploy-policy.json
```

La policy agrupa permisos por servicio (`STS`, `S3`, `EC2` e `IAM`) y usa `Resource: "*"` para no depender del account ID ni de la identidad de un alumno. Está pensada para una cuenta educativa donde Terraform debe crear y destruir los recursos de este lab y puede reutilizarse en otros labs que trabajen con esos mismos servicios.

No es una policy para producción ni debe asociarse a las EC2. Se adjunta al role OIDC que asume GitHub Actions. Las policies runtime de las EC2 continúan separadas porque representan los permisos que la aplicación o instancia necesita durante su ejecución.

El workflow crea automáticamente un role y un instance profile para cada EC2. No hace falta cargar `EC2_INSTANCE_PROFILE_NAME` en GitHub.

Cada role recibe inicialmente:

- `AmazonSSMManagedInstanceCore`;
- `s3-lab02-full-buckets`, limitada a los dos buckets de este laboratorio.

La policy amplia es el punto de partida. Se conserva durante la carga inicial desde local y luego se retira desde IAM Console para aplicar la segmentación final.

## Desplegar Infraestructura

1. En GitHub, abre `Actions`.
2. Ejecuta el workflow `M4-C1 Infra Deploy`.
3. Selecciona `plan` para revisar la infraestructura.
4. Si el plan es correcto, ejecuta el mismo workflow con `apply`.
5. Revisa los outputs del workflow y anota `bucket_a_name`, `bucket_b_name`, `backend_role_names` y `backend_instance_profile_names`.

El workflow ejecuta `terraform fmt -check`, `terraform init` con backend S3 remoto, `terraform validate` y luego `plan`, `apply` o `destroy` segun la opcion manual.

## Preparar Datos Iniciales

Podés popular los buckets desde tu máquina local o desde el Dev Container, sin ingresar a una EC2. Primero ejecutá `apply` y confirmá que Terraform creó `bucket_a_name` y `bucket_b_name`.

El script calcula los nombres de bucket a partir de tu account number y `student-id`, verifica la identidad AWS activa, comprueba que ambos buckets existan y carga:

```text
folder-a/a.txt
folder-b/b.txt
shared/shared.txt
```

Ejecutalo desde la raíz del repositorio:

```bash
./labs/m4-c1-lab/scripts/popular-s3-desde-local.sh <account-number> <student-id>
```

Ejemplo:

```bash
./labs/m4-c1-lab/scripts/popular-s3-desde-local.sh 123456789012 perez-ana
```

El script usa `AWS_REGION` si está definida; de lo contrario utiliza `us-east-1`. No crea buckets, roles, policies ni otros recursos y no usa `--delete`.

Antes de ejecutarlo, verificá tu sesión AWS:

```bash
aws sts get-caller-identity --region us-east-1
```

El script crea los archivos en un directorio temporal y lo elimina al terminar. No se crean archivos de prueba dentro de las EC2.

Una vez completada la carga local, las EC2 se utilizan únicamente para abrir sesiones de Session Manager y validar las operaciones S3 permitidas o rechazadas según el role IAM asignado a cada instancia.

## Validar Acceso desde las EC2

Conectate por Session Manager a la instancia indicada y ejecutá las pruebas de la matriz de permisos. Usá los nombres reales de los buckets mostrados por Terraform:

```bash
aws s3 ls s3://<bucket-a>/
aws s3 ls s3://<bucket-b>/
aws s3 cp s3://<bucket-a>/shared/shared.txt /tmp/shared.txt
aws s3 cp /tmp/test.txt s3://<bucket-b>/folder-b/test.txt
aws s3 rm s3://<bucket-b>/folder-b/test.txt
```

Las operaciones no autorizadas deben devolver `AccessDenied`. La guía [LAB02](guias/guia-seguridad-lab02-ec2-red-s3.md) contiene la matriz completa de comandos permitidos y denegados para `backend-a-01`, `backend-a-02`, `backend-b-01` y `backend-b-02`.

## Revisar Acceso Amplio Inicial

En la consola de AWS:

1. Abre IAM.
2. Entra a los roles preasociados a las EC2 del lab.
3. Verifica que todavia tengan `AmazonSSMManagedInstanceCore`.
4. Verifica que inicialmente tengan la politica amplia `s3-lab02-full-buckets`.

Conectate por Session Manager a `backend-a-02` y demuestra que el acceso amplio permite listar o leer ambos buckets:

```bash
aws s3 ls s3://<bucket-a>/
aws s3 ls s3://<bucket-b>/
aws s3 cp s3://<bucket-b>/shared/shared.txt /tmp/shared-from-b.txt
```

Este acceso amplio es intencional solo para observar el punto de partida.

## Retirar Politica Amplia

Desde IAM, entra rol por rol y quita `s3-lab02-full-buckets`.

Conserva `AmazonSSMManagedInstanceCore`; si la quitas, Session Manager puede dejar de funcionar.

## Crear Politicas Finales Manualmente

Crea manualmente cuatro politicas IAM y asocialas al rol correspondiente de cada EC2. Reemplaza `<bucket-a>` y `<bucket-b>` por los nombres reales.

### backend-a-01: Full S3-A

Permite control completo sobre el bucket A:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
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

### backend-a-02: Lectura Completa S3-A

Permite listar y leer todo el bucket A:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": "s3:ListBucket",
      "Resource": "arn:aws:s3:::<bucket-a>"
    },
    {
      "Effect": "Allow",
      "Action": "s3:GetObject",
      "Resource": "arn:aws:s3:::<bucket-a>/*"
    }
  ]
}
```

### backend-b-01: Shared de S3-A y Full S3-B

Permite listar solo el prefijo `shared/` de bucket A, leer objetos bajo `shared/` en bucket A y control completo sobre bucket B:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": "s3:ListBucket",
      "Resource": "arn:aws:s3:::<bucket-a>",
      "Condition": {
        "StringLike": {
          "s3:prefix": [
            "shared",
            "shared/*"
          ]
        }
      }
    },
    {
      "Effect": "Allow",
      "Action": "s3:GetObject",
      "Resource": "arn:aws:s3:::<bucket-a>/shared/*"
    },
    {
      "Effect": "Allow",
      "Action": "s3:*",
      "Resource": [
        "arn:aws:s3:::<bucket-b>",
        "arn:aws:s3:::<bucket-b>/*"
      ]
    }
  ]
}
```

### backend-b-02: Lectura S3-B y Escritura Solo folder-b

Permite listar y leer todo bucket B, pero crear y borrar solo en `folder-b/`:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": "s3:ListBucket",
      "Resource": "arn:aws:s3:::<bucket-b>"
    },
    {
      "Effect": "Allow",
      "Action": "s3:GetObject",
      "Resource": "arn:aws:s3:::<bucket-b>/*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "s3:PutObject",
        "s3:DeleteObject"
      ],
      "Resource": "arn:aws:s3:::<bucket-b>/folder-b/*"
    }
  ]
}
```

## Matriz Esperada

| Instancia | Bucket A | Bucket B |
| --- | --- | --- |
| `backend-a-01` | Listar, leer, subir y borrar todo | Denegado |
| `backend-a-02` | Listar y leer todo | Denegado |
| `backend-b-01` | Listar y leer solo `shared/` | Listar, leer, subir y borrar todo |
| `backend-b-02` | Denegado | Listar y leer todo; subir y borrar solo `folder-b/` |

Comandos utiles para comprobar:

```bash
aws s3 ls s3://<bucket-a>/
aws s3 ls s3://<bucket-a>/shared/
aws s3 cp s3://<bucket-a>/shared/shared.txt /tmp/shared.txt
aws s3 cp /tmp/test.txt s3://<bucket-b>/folder-b/test.txt
aws s3 rm s3://<bucket-b>/folder-b/test.txt
aws s3 cp /tmp/test.txt s3://<bucket-b>/folder-a/test.txt
```

Cuando una accion no corresponde a la politica final, espera `AccessDenied`.

## Limpieza Segura

1. Si creaste politicas IAM manuales para este lab, desasocialas y eliminalas desde IAM.
2. Mantener o quitar los roles SSM base depende de la indicacion de aula; recuerda que estan fuera de Terraform.
3. En GitHub Actions, ejecuta `M4-C1 Infra Deploy` con `destroy` para eliminar la infraestructura Terraform.

Los roles y politicas IAM de consola son intencionalmente externos a Terraform en este laboratorio.
