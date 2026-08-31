# Avisos diarios de recursos AWS

Este stack crea una automatizacion para detectar recursos AWS que conviene revisar antes de terminar un laboratorio. La unica entrada que tenes que proporcionar es tu direccion de email.

## Que crea

```text
EventBridge (una vez por dia)
          |
          v
Lambda de inventario -----> SNS -----> tu email
          |
          +-- APIs de lectura de EC2, EBS, RDS, ELB, Lambda,
              DynamoDB, S3 y ECR
```

El stack no elimina recursos y no necesita access keys. La Lambda usa un role propio con permisos de lectura de inventario y permiso para publicar solamente en el topic SNS del stack.

Además de consultar los servicios regionales, el role tiene `ce:GetCostAndUsage` y `ce:GetCostForecast` para leer el resumen financiero de Cost Explorer desde su endpoint regional de Billing.

## Importante: confirmacion del email

SNS envia un mensaje de confirmacion a la direccion indicada durante la creacion del stack. Tenes que abrir ese mensaje y seleccionar **Confirm subscription**.

Hasta confirmar la suscripcion, la Lambda puede ejecutarse correctamente pero no vas a recibir el aviso. La confirmacion es un paso externo a CloudFormation.

## Desplegar desde AWS Console

1. Descargá `resource-alerts-stack.yaml` desde este repositorio.
2. Abrí CloudFormation en la region donde queres revisar recursos.
3. Elegí **Create stack → With new resources (standard)**.
4. Seleccioná **Upload a template file** y cargá el YAML.
5. En parámetros, completá solamente **Email para recibir avisos**.
6. Avanzá hasta la pantalla final.
7. Marcá la casilla que reconoce que CloudFormation puede crear recursos IAM.
8. Creá el stack.
9. Confirmá la suscripcion SNS desde el email recibido.
10. Revisá la pestaña **Resources** y los **Outputs** del stack.

El schedule es `rate(1 day)`. EventBridge puede ejecutar la primera revisión aproximadamente 24 horas después de crear o modificar la regla; no se debe interpretar como una ejecución inmediata.

## Desplegar desde AWS CLI

Usá una sesión AWS autorizada y la región que quieras revisar. El comando no crea recursos fuera del stack:

```bash
aws cloudformation deploy \
  --template-file recursos/aws-resource-alerts/resource-alerts-stack.yaml \
  --stack-name resource-alerts-<tu-identidad> \
  --parameter-overrides NotificationEmail=tu-mail@example.com \
  --capabilities CAPABILITY_NAMED_IAM \
  --region us-east-1
```

Verificá el resultado:

```bash
aws cloudformation describe-stacks \
  --stack-name resource-alerts-<tu-identidad> \
  --query 'Stacks[0].Outputs' \
  --output table \
  --region us-east-1
```

Después confirmá la suscripcion SNS desde tu email.

## Resumen financiero

Cada aviso incluye un resumen de Cost Explorer:

- uso acumulado del período actual;
- créditos aplicados al período;
- impuestos informados por Cost Explorer;
- neto estimado del período;
- forecast estimado para el próximo período de facturación.

El saldo de créditos disponibles no se muestra como un número inventado: la API utilizada por esta herramienta no expone un saldo restante general. Para ese dato, revisá **Billing → Credits** en la consola de AWS. Cost Explorer puede tener demora y el forecast es una estimación, no un límite de gasto.

## Que informa la Lambda

La revisión busca recursos existentes o activos que pueden producir costo o requerir limpieza:

- instancias EC2 en cualquier estado no eliminado;
- volúmenes y snapshots EBS;
- NAT Gateways;
- Elastic IP asignadas;
- instancias y clusters RDS;
- load balancers;
- funciones Lambda desplegadas;
- tablas DynamoDB;
- buckets S3;
- repositorios ECR.

Siempre envía el resumen financiero cuando la consulta está disponible. Si encuentra recursos, agrega un listado agrupado por tipo con nombre, ID/ARN y estado. Si no encuentra elementos, informa que la región está limpia según las consultas realizadas.

## Probar sin esperar un día

La ejecución manual sirve para comprobar la Lambda y el email después de confirmar la suscripción:

```bash
aws lambda invoke \
  --function-name resource-alerts-<nombre-del-stack> \
  --region us-east-1 \
  /tmp/resource-alert-response.json
cat /tmp/resource-alert-response.json
```

No ejecutes la prueba manual hasta que la suscripción SNS esté confirmada. La respuesta esperada es similar a:

```json
{"alert_sent": true, "resource_count": 1, "billing_available": true}
```

Si la cuenta no tiene recursos detectables, la respuesta esperada es:

```json
{"alert_sent": true, "resource_count": 0, "billing_available": true}
```

También podés revisar el log de la función en CloudWatch Logs.

## Limitaciones

- El inventario no es una medición de costo en tiempo real. Para costos y cargos reales revisá Cost Explorer y Billing.
- La información de costos puede tener demora y algunos servicios o regiones pueden no estar representados por estas consultas.
- S3 es un servicio global: los buckets se listan desde la cuenta aunque la Lambda se ejecute en una región concreta.
- La detección identifica recursos existentes que conviene revisar; no decide si son necesarios ni los elimina.
- Una Lambda, una tabla DynamoDB o un repositorio ECR pueden tener costos y condiciones diferentes según su uso, configuración y almacenamiento.
- El stack revisa una sola región para los servicios regionales. Si usaste varias regiones, desplegá una instancia del stack por región con un email o topic de notificación apropiado.
- El stack usa `rate(1 day)`, no una hora exacta garantizada.

## Cleanup

Cuando ya no necesites la automatización, eliminá el stack:

```bash
aws cloudformation delete-stack \
  --stack-name resource-alerts-<tu-identidad> \
  --region us-east-1

aws cloudformation wait stack-delete-complete \
  --stack-name resource-alerts-<tu-identidad> \
  --region us-east-1
```

Desde la consola: **CloudFormation → seleccioná el stack → Delete**.

La eliminación quita la Lambda, el role IAM, la regla EventBridge, el topic SNS y la suscripción creada por el stack. No elimina ninguno de los recursos que la Lambda haya detectado.

Antes de terminar una clase, verificá también manualmente la consola de EC2, VPC, RDS, S3, DynamoDB, ELB, Lambda y ECR si trabajaste en más de una región.

## Validación local

Desde la raíz del repositorio:

```bash
bash recursos/aws-resource-alerts/scripts/validate.sh
```

La validación comprueba la sintaxis YAML básica, los recursos principales, el parámetro único, la ausencia de APIs destructivas y los permisos explícitos de solo lectura.
