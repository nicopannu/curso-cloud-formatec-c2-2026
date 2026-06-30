# LAB01 IaC - Terraform S3 basico

Proyecto Terraform minimo para explicar Infrastructure as Code en AWS.

## Que crea

Un bucket S3 privado con:

- nombre unico generado con `random_id`;
- bloqueo de acceso publico;
- versionado habilitado;
- cifrado SSE-S3;
- tags comunes aplicados desde `default_tags` del provider.

## Por que S3

S3 permite explicar el ciclo completo de Terraform sin montar una arquitectura grande:

- provider;
- recurso real;
- variables;
- outputs;
- plan;
- state;
- cambio controlado;
- destroy.

El objetivo pedagogico no es construir una solucion de storage, sino mostrar que la infraestructura puede ser declarada, revisada, aplicada y limpiada de forma repetible.

## Archivos

| Archivo | Rol |
|---|---|
| `versions.tf` | Version minima de Terraform y providers requeridos |
| `providers.tf` | Configuracion del provider AWS y tags comunes |
| `variables.tf` | Parametros modificables del lab |
| `main.tf` | Recursos AWS declarados |
| `outputs.tf` | Datos visibles luego del apply |
| `terraform.tfvars.example` | Ejemplo seguro de variables, sin secretos |

## Flujo seguro sin crear recursos

```bash
terraform init -backend=false
terraform fmt -check
terraform validate
terraform plan
```

`plan` consulta AWS y prepara una propuesta de cambios, pero no crea recursos.

Si se usa el perfil AWS del curso desde el entorno del docente:

```bash
AWS_PROFILE=curso terraform plan
```

## Flujo con recursos reales

Ejecutar solo con autorizacion del docente y en cuenta sandbox/laboratorio:

```bash
terraform apply
terraform output
terraform destroy
```

Con perfil del curso:

```bash
AWS_PROFILE=curso terraform apply
AWS_PROFILE=curso terraform output
AWS_PROFILE=curso terraform destroy
```

## Variables

Se puede copiar el ejemplo:

```bash
cp terraform.tfvars.example terraform.tfvars
```

`terraform.tfvars` esta ignorado por Git para evitar subir valores locales. No guardar secretos en variables versionadas.

## Limpieza

Si se ejecuto `apply`, cerrar con:

```bash
terraform destroy
```

Verificar que el bucket no quede creado. El cleanup forma parte del laboratorio, no es un paso opcional cuando se trabajaron recursos reales.
