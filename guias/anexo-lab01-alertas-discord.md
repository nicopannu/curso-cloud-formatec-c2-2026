# Anexo LAB01 — De una alarma de CloudWatch a una alerta en Discord

**Módulo:** M3-C5 — Monitoreo proactivo
**Formato:** extensión opcional por consola
**Duración estimada:** 25 minutos

---

## Contexto

En LAB01 creaste alarmas que cambian de estado dentro de CloudWatch. Un equipo no opera mirando permanentemente la consola: necesita recibir una alerta en un canal compartido.

En esta extensión, Banco Patacon publica en Discord los cambios de estado de sus alarmas.

```text
CloudWatch Alarm → SNS Topic → Lambda → Discord webhook → #alertas-cloudwatch
```

Una alarma es una condición técnica. Una alerta operativa agrega un canal, una audiencia y un primer paso de investigación.

---

## Objetivos

- Diferenciar una alarma de CloudWatch de una alerta operativa.
- Configurar una entrega de alarmas a un canal de Discord sin exponer el webhook.
- Usar SNS como canal de eventos y Lambda para adaptar el mensaje.
- Verificar una alerta a partir del incidente simulado de LAB01.

---

## Alcance

**Obligatorio en LAB01:** crear e interpretar metric filters, dashboard y alarmas.

**Opcional en este anexo:** publicar los cambios de estado de las alarmas en Discord.

No copies la URL del webhook en archivos, variables de GitHub ni Terraform versionado. Es un secreto con permiso de publicar en el canal.

---

## Pre-requisitos

- LAB01 completado hasta la creación de `Frontend5xxAlarm` y `BackendErroresAlarm`.
- Un canal de Discord, por ejemplo `#alertas-cloudwatch`.
- Un webhook creado para ese canal. Conservá su URL para cargarla en Parameter Store; no la compartas en el chat ni la subas al repositorio.
- Permisos para usar CloudWatch, SNS, Lambda, IAM y Systems Manager Parameter Store en `us-east-1`.

---

## Actividad 1 — Crear el parámetro secreto (3 min)

1. Abrí **AWS Systems Manager → Parameter Store → Create parameter**.
2. Completá:

   | Campo | Valor |
   |---|---|
   | Name | `/formatec/m3c5/discord-webhook` |
   | Tier | Standard |
   | Type | SecureString |
   | Value | URL del webhook de `#alertas-cloudwatch` |

3. Elegí la clave administrada por AWS para Parameter Store, salvo que el curso indique una clave KMS propia.
4. Creá el parámetro.

### Checkpoint 1

El valor del webhook no aparece en el repositorio ni en la configuración visible de la Lambda. Sólo queda guardado como `SecureString`.

---

## Actividad 2 — Crear el topic SNS (3 min)

1. Abrí **Amazon SNS → Topics → Create topic**.
2. Elegí tipo **Standard**.
3. Usá:

   ```text
   Name: BancoPatacon-Alertas-Discord
   ```

4. Creá el topic y guardá su ARN.

SNS recibe la notificación de CloudWatch. Discord no se suscribe directamente: la Lambda transforma el evento antes de enviarlo al webhook.

---

## Actividad 3 — Crear la Lambda relay (8 min)

1. Abrí **AWS Lambda → Create function → Author from scratch**.
2. Completá:

   | Campo | Valor |
   |---|---|
   | Function name | `banco-patacon-discord-relay` |
   | Runtime | Python 3.12 o posterior disponible |
   | Architecture | x86_64 |
   | Execution role | Create a new role with basic Lambda permissions |

3. Después de crearla, configurá **Configuration → General configuration → Edit**:

   ```text
   Timeout: 10 seconds
   ```

4. En **Configuration → Environment variables**, agregá:

   ```text
   DISCORD_WEBHOOK_PARAMETER=/formatec/m3c5/discord-webhook
   ```

5. En el rol de ejecución, agregá una política inline que permita leer únicamente ese parámetro:

   ```json
   {
     "Version": "2012-10-17",
     "Statement": [
       {
         "Effect": "Allow",
         "Action": "ssm:GetParameter",
         "Resource": "arn:aws:ssm:us-east-1:<tu-account-id>:parameter/formatec/m3c5/discord-webhook"
       }
     ]
   }
   ```

6. Reemplazá el código por:

```python
import json
import os
import urllib.request

import boto3

ssm = boto3.client("ssm")


def discord_webhook_url():
    parameter_name = os.environ["DISCORD_WEBHOOK_PARAMETER"]
    response = ssm.get_parameter(Name=parameter_name, WithDecryption=True)
    return response["Parameter"]["Value"]


def handler(event, context):
    webhook = discord_webhook_url()

    for record in event["Records"]:
        message = record["Sns"]["Message"]
        try:
            alarm = json.loads(message)
        except json.JSONDecodeError:
            alarm = {"AlarmName": "Evento SNS", "NewStateValue": "UNKNOWN", "NewStateReason": message}

        state = alarm.get("NewStateValue", "UNKNOWN")
        emoji = {"ALARM": "🚨", "OK": "✅", "INSUFFICIENT_DATA": "⚠️"}.get(state, "ℹ️")
        color = {"ALARM": 15158332, "OK": 3066993, "INSUFFICIENT_DATA": 15844367}.get(state, 9807270)

        payload = {
            "embeds": [
                {
                    "title": f"{emoji} Banco Patacon — {alarm.get('AlarmName', 'Alarma sin nombre')}",
                    "color": color,
                    "fields": [
                        {"name": "Estado", "value": state, "inline": True},
                        {"name": "Región", "value": alarm.get("Region", "us-east-1"), "inline": True},
                        {"name": "Razón", "value": alarm.get("NewStateReason", "Sin detalle")[:1000], "inline": False},
                        {"name": "Primer paso", "value": "Revisar el dashboard y los logs del componente afectado.", "inline": False},
                    ],
                }
            ]
        }

        request = urllib.request.Request(
            webhook,
            data=json.dumps(payload).encode("utf-8"),
            headers={"Content-Type": "application/json"},
            method="POST",
        )
        with urllib.request.urlopen(request, timeout=5) as response:
            if response.status not in (200, 204):
                raise RuntimeError(f"Discord respondió HTTP {response.status}")

    return {"statusCode": 200}
```

> La función debe permanecer fuera de una VPC salvo que esa VPC tenga salida a Internet mediante NAT. El webhook de Discord es un endpoint público HTTPS.

### Checkpoint 2

La Lambda tiene una variable con el **nombre** del parámetro, no con la URL del webhook. Su rol sólo puede ejecutar `ssm:GetParameter` sobre ese parámetro.

---

## Actividad 4 — Conectar SNS con la Lambda (3 min)

1. Abrí la función Lambda.
2. Elegí **Add trigger**.
3. Seleccioná **SNS** y elegí el topic `BancoPatacon-Alertas-Discord`.
4. Confirmá la suscripción.

SNS ahora invoca la Lambda por cada mensaje que reciba.

---

## Actividad 5 — Asociar las alarmas al topic (3 min)

Para cada alarma del LAB01:

1. Abrí **CloudWatch → Alarms**.
2. Seleccioná la alarma y elegí **Edit**.
3. En **Notification**, para el estado `In alarm`, seleccioná:

   ```text
   Send notification to: BancoPatacon-Alertas-Discord
   ```

4. Guardá.

Repetí para `Frontend5xxAlarm` y `BackendErroresAlarm`.

### Checkpoint 3

La alarma conserva su condición y período de evaluación. Sólo agrega una acción cuando cambia al estado `ALARM`.

---

## Actividad 6 — Probar la alerta (5 min)

1. Confirmá que las alarmas están en `OK` o `INSUFFICIENT_DATA`.
2. Ejecutá el incidente de LAB01:

   ```bash
   ./scripts/generar-trafico.sh <FRONTEND_URL> <BACKEND_URL> 600
   ```

3. Esperá los períodos de evaluación configurados.
4. Verificá:

   - la alarma cambia a `ALARM`;
   - SNS invoca la Lambda;
   - aparece un mensaje en `#alertas-cloudwatch`;
   - CloudWatch Logs de la Lambda no muestra errores.

### Entregables opcionales

- Captura de la alarma en estado `ALARM`.
- Captura del mensaje de Discord sin mostrar la URL del webhook.
- Nombre del topic SNS y de la Lambda.
- Una explicación breve de por qué SNS no publica directamente en Discord.

### Criterios de evaluación opcionales

| Criterio | Evidencia |
|---|---|
| Protección del secreto | URL ausente del repositorio y guardada como `SecureString` |
| Integración | Alarma → SNS → Lambda → Discord completa |
| Interpretación | El mensaje identifica alarma, estado y primer paso operativo |
| Cleanup | Recursos temporales eliminados o identificados como demo persistente |

---

## Cleanup

Si esta integración es sólo para una demostración temporal:

1. Quitá la acción SNS de las alarmas.
2. Eliminá la suscripción SNS a la Lambda.
3. Eliminá el topic SNS.
4. Eliminá la Lambda.
5. Eliminá el parámetro `/formatec/m3c5/discord-webhook`.
6. Eliminá el rol de Lambda sólo si fue creado exclusivamente para esta demo.

Si el canal seguirá siendo parte de la comunidad del curso, conservá la integración y rotá el webhook si se expuso accidentalmente.

---

## Cierre

La alarma detecta una condición. El relay transforma esa condición en un mensaje accionable para un equipo. La respuesta sigue requiriendo revisar dashboard, logs y contexto de aplicación antes de concluir la causa del incidente.
