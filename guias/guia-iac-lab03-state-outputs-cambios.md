# Guia LAB03: Outputs, state y cambios controlados

**Modulo:** M3 - Clase 1: Infrastructure as Code  
**Duracion estimada:** 90 a 120 minutos  
**Proyecto Terraform:** continuacion de `terraform/iac-lab02-lambda/`  
**Nivel:** introductorio/intermedio  

---

## 1. Contexto

En LAB01 creaste un bucket S3 con Terraform. En LAB02 creaste una Lambda, agregaste variables con `terraform.tfvars` y usaste outputs para obtener datos utiles.

En este laboratorio vas a trabajar sobre infraestructura ya creada. El objetivo es entender como Terraform analiza cambios, que informacion guarda en el state y como usar outputs sin buscar datos manualmente en la consola AWS.

La pregunta central es:

> Cuando cambio un archivo, como decide Terraform que tiene que crear, modificar o reemplazar?

---

## 2. Objetivos de aprendizaje

Al finalizar el LAB03 vas a poder:

1. Consultar outputs con `terraform output`.
2. Listar recursos administrados con `terraform state list`.
3. Inspeccionar el estado con `terraform show`.
4. Diferenciar cambios de codigo Lambda y cambios de configuracion Terraform.
5. Leer un `terraform plan` antes de aplicar cambios.
6. Explicar la relacion entre archivos `.tf`, state local y recursos reales en AWS.
7. Limpiar recursos con `terraform destroy`.

---

## 3. Arquitectura de trabajo

```text
Proyecto Terraform LAB02
      |
      | main.tf / variables.tf / terraform.tfvars / outputs.tf
      v
Terraform CLI
      |
      | state local + provider AWS
      v
AWS Lambda + IAM Role
      |
      | aws lambda invoke
      v
Respuesta de la funcion
```

Este lab no agrega nuevos servicios. Profundiza en como se gestionan cambios sobre la Lambda del LAB02.

---

## 4. Alcance del LAB03

### Incluido

- Revision de outputs.
- Revision de state local.
- Cambio de codigo de Lambda.
- Cambio de una variable simple.
- Lectura del plan antes de aplicar.
- Invocacion de Lambda para validar resultado.
- Limpieza final.

### No incluido todavia

- Data sources.
- Locals.
- Modulos.
- Backend remoto.
- Import de recursos existentes.
- Workspaces.

---

## 5. Pre-requisitos

Necesitas haber completado LAB02 o tener un proyecto equivalente con:

```text
terraform/iac-lab02-lambda/
  versions.tf
  providers.tf
  variables.tf
  terraform.tfvars
  main.tf
  outputs.tf
  function/lambda_function.py
```

Validar identidad AWS:

```powershell
aws sts get-caller-identity
```

Entrar al proyecto:

```powershell
cd terraform/iac-lab02-lambda
```

Validar Terraform:

```powershell
terraform fmt
terraform validate
```

Si no aplicaste LAB02 todavia, ejecutar:

```powershell
terraform plan
terraform apply
```

Confirmar con `yes` solo si tenes autorizacion para crear recursos.

---

## 6. Revisar outputs

Ejecutar:

```powershell
terraform output
```

Obtener solo el nombre de la funcion:

```powershell
terraform output -raw lambda_function_name
```

Guardar el nombre en una variable de PowerShell:

```powershell
$FUNCTION_NAME = terraform output -raw lambda_function_name
```

Checkpoint:

- Que diferencia hay entre ver todos los outputs y pedir uno con `-raw`?
- Por que conviene obtener el nombre desde Terraform y no copiarlo desde consola?

---

## 7. Invocar la Lambda actual

Ejecutar:

```powershell
aws lambda invoke `
  --function-name $FUNCTION_NAME `
  --payload '{}' `
  --cli-binary-format raw-in-base64-out `
  response.json

Get-Content response.json
```

Resultado esperado inicial:

```json
{"statusCode":200,"body":"hola desde lambda"}
```

Si el resultado no coincide, revisar:

```powershell
terraform output
aws lambda get-function --function-name $FUNCTION_NAME
```

---

## 8. Revisar recursos en state

Listar recursos que Terraform administra:

```powershell
terraform state list
```

Deberias ver recursos similares a:

```text
data.archive_file.lambda_zip
aws_iam_role.lambda_role
aws_iam_role_policy_attachment.lambda_basic_logs
aws_lambda_function.hola
```

Inspeccionar el estado completo:

```powershell
terraform show
```

Checkpoint:

- Que recursos aparecen en el state?
- Aparece el archivo ZIP local?
- Aparece el nombre real de la Lambda?
- El state es documentacion para humanos o informacion operativa?

---

## 9. Cambiar codigo de Lambda

Editar `function/lambda_function.py`:

```python
def lambda_handler(event, context):
    return {
        "statusCode": 200,
        "body": "hola desde lambda - cambio controlado"
    }
```

Revisar formato y plan:

```powershell
terraform fmt
terraform plan
```

Buscar en el plan cambios relacionados con:

```text
source_code_hash
```

Ese valor cambia porque Terraform vuelve a calcular el hash del ZIP de la funcion.

Checkpoint:

- Terraform detecto que cambio el codigo?
- El nombre de la Lambda cambia?
- El rol IAM cambia?
- El cambio parece una modificacion o una recreacion completa?

---

## 10. Aplicar el cambio

Si el plan muestra el cambio esperado y tenes autorizacion:

```powershell
terraform apply
```

Confirmar con:

```text
yes
```

Volver a invocar:

```powershell
aws lambda invoke `
  --function-name $FUNCTION_NAME `
  --payload '{}' `
  --cli-binary-format raw-in-base64-out `
  response.json

Get-Content response.json
```

Resultado esperado:

```json
{"statusCode":200,"body":"hola desde lambda - cambio controlado"}
```

---

## 11. Cambiar una variable

Editar `terraform.tfvars` y cambiar el valor de `student_identity`.

Ejemplo:

```hcl
student_identity = "tu-identidad-2"
```

Ejecutar:

```powershell
terraform plan
```

Revisar si el cambio afecta:

- variables de entorno de la Lambda;
- nombre de la Lambda;
- rol IAM;
- outputs.

Importante: si cambias `lambda_name`, Terraform puede necesitar reemplazar recursos. Leer el plan antes de aplicar.

Checkpoint:

- Que cambio genera modificar `student_identity`?
- Que cambio genera modificar `lambda_name`?
- Que diferencia hay entre actualizar una funcion y reemplazarla?

---

## 12. Volver a un estado conocido

Dejar `terraform.tfvars` con los valores que queres mantener para el lab.

Ejecutar:

```powershell
terraform fmt
terraform validate
terraform plan
```

Si el plan coincide con lo esperado:

```powershell
terraform apply
```

---

## 13. Limpieza

Antes de destruir, guardar el nombre de la Lambda:

```powershell
$FUNCTION_NAME = terraform output -raw lambda_function_name
```

Destruir recursos:

```powershell
terraform destroy
```

Confirmar con:

```text
yes
```

Borrar log group si existe:

```powershell
aws logs delete-log-group --log-group-name "/aws/lambda/$FUNCTION_NAME"
```

Si AWS responde que no existe, no hay nada mas para borrar.

---

## 14. Troubleshooting

| Problema | Causa probable | Accion sugerida |
|---|---|---|
| `terraform output` no muestra valores | Todavia no se ejecuto `apply` | Ejecutar `terraform plan` y luego `apply` si esta autorizado |
| `state list` no muestra recursos | No hay state local o se esta en otra carpeta | Verificar `pwd`/ubicacion y archivos del proyecto |
| Invoke devuelve mensaje viejo | No se aplico el cambio o se invoco otra funcion | Revisar `$FUNCTION_NAME`, `terraform output` y ejecutar `terraform apply` |
| Plan propone reemplazar recursos | Cambio un atributo que fuerza recreacion | Leer el plan completo antes de confirmar |
| Error de permisos en Lambda | Credenciales o IAM insuficientes | Validar cuenta con `aws sts get-caller-identity` |

---

## 15. Entregables

Entregar:

1. Salida de `terraform output`.
2. Salida de `terraform state list`.
3. Captura o fragmento del plan donde se vea el cambio de Lambda.
4. Respuesta de la Lambda antes y despues del cambio.
5. Explicacion breve: que cambio se hizo y como lo detecto Terraform.
6. Confirmacion de limpieza si se ejecuto `destroy`.

---
