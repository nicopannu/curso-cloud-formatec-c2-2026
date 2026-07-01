# LAB01 - Terraform minimo con S3

Este proyecto muestra la estructura minima de Terraform para crear un primer recurso en AWS.

## Objetivo

Crear un bucket S3 usando Terraform con la menor cantidad de piezas posibles:

- `versions.tf`: version de Terraform y provider requerido.
- `providers.tf`: configuracion del provider AWS.
- `main.tf`: recurso que se quiere crear.

## Archivos

| Archivo | Rol |
|---|---|
| `versions.tf` | Declara que provider necesita Terraform para hablar con AWS. |
| `providers.tf` | Configura AWS como destino y define la region. |
| `main.tf` | Declara el recurso S3 que Terraform debe administrar. |

En este LAB01 no hay:

- `variables.tf`
- `terraform.tfvars`
- `outputs.tf`
- `locals`
- `modules`
- backend remoto

Esos temas se trabajan en los siguientes laboratorios.

## Nombre del bucket

En `main.tf` el nombre esta escrito directamente:

```hcl
resource "aws_s3_bucket" "lab" {
  bucket = "s3-bucket-485617552563-np"
}
```

Antes de ejecutar `terraform plan` o `terraform apply`, cada alumno debe cambiarlo por un nombre propio siguiendo el patron:

```text
s3-bucket-NUMERO_DE_CUENTA-INICIALES
```

Ejemplo:

```text
s3-bucket-485617552563-np
```

S3 exige nombres globalmente unicos. Si el nombre ya existe, AWS va a rechazar la creacion del bucket.

## Comandos de trabajo

Inicializar Terraform sin backend remoto:

```powershell
terraform init -backend=false
```

Formatear archivos:

```powershell
terraform fmt
```

Validar sintaxis:

```powershell
terraform validate
```

Ver el plan:

```powershell
terraform plan
```

Crear recursos solo cuando tengas autorizacion para usar AWS:

```powershell
terraform apply
```

Limpiar recursos al terminar:

```powershell
terraform destroy
```

## Progresion prevista

- LAB01: estructura minima de proyecto Terraform y primer recurso S3.
- LAB02: variables para no hardcodear region, cuenta, iniciales y nombres.
- LAB03: Lambda reutilizando variables ya definidas.
- LAB04: modulos para organizar infraestructura repetible.
- LAB05: backend remoto con bucket S3 y tabla DynamoDB para estado y bloqueo.
