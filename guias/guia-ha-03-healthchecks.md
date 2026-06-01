# Guia HA-03: Alta Disponibilidad - Health Checks y Resiliencia de Proceso

**Objetivo:** Entender la diferencia entre EC2 health check y ELB health check en el contexto de un Auto Scaling Group. Simular fallas reales de proceso y observar como el sistema responde segun la configuracion de health checks activa. Aprender la diferencia entre shallow y deep health checks.

**Duracion estimada:** 2 horas

**Módulo:** Módulo 2 — Clase 2: Alta Disponibilidad

---

## Contexto

En los labs anteriores, el Auto Scaling Group de CloudCuyo tiene una configuracion de health checks por defecto: **EC2 health checks**. Esto significa que el ASG solo reemplaza una instancia si la propia plataforma EC2 reporta un problema de hardware o red con esa VM.

El problema es que esto no cubre el caso mas comun de falla en produccion: **el proceso de la aplicacion se cae, pero la VM sigue encendida**. Desde el punto de vista de EC2, la instancia esta perfectamente "sana". El ASG no hace nada. La instancia sigue en el pool de targets, pero el ALB la va a marcar Unhealthy y va a dejar de enviarle trafico.

Resultado: el grupo queda con menos capacidad de la deseada (por ejemplo 1 instancia en lugar de 2), sin que nadie lo note automaticamente.

La solucion es habilitar **ELB health checks** en el ASG. Cuando esta habilitado, el ASG usa el estado del ALB para determinar la salud de sus instancias. Si el ALB marca una instancia como Unhealthy, el ASG la reemplaza automaticamente.

Este lab demuestra ambos comportamientos con experimentos controlados.

---

## Arquitectura del experimento

```
+------------------------------------------------------------+
|  Experimento 1: solo EC2 health check                      |
|                                                            |
|  +----------------+    kill gunicorn    +------------+    |
|  | Traffic Gen    | -----------------> | api-node-1 |    |
|  | (SSM session)  |                    | [RUNNING]  |    |
|  +----------------+                    | gunicorn X |    |
|                                        +------------+    |
|                                                           |
|  ALB → marca api-node-1 como Unhealthy                   |
|  ASG → NO reemplaza (EC2 sigue "healthy" para EC2)       |
|  Capacidad: 1/2 instancias activas                       |
+------------------------------------------------------------+

+------------------------------------------------------------+
|  Experimento 2: EC2 + ELB health check habilitado          |
|                                                            |
|  api-node-1 sigue Unhealthy en el TG (del Exp. 1)         |
|                                                            |
|  ASG detecta estado ELB = Unhealthy                       |
|  ASG → Termina api-node-1                                 |
|  ASG → Lanza nueva instancia de reemplazo                 |
|  Capacidad: vuelve a 2/2 instancias activas               |
+------------------------------------------------------------+

+------------------------------------------------------------+
|  Experimento 3: shallow vs deep health check               |
|                                                            |
|  /health      → verifica proceso local (rapido, estable)  |
|  /health/deep → simula verificar dependencia externa      |
|                                                            |
|  Trade-off: deep check puede causar reemplazos en         |
|  cascada si una dependencia falla en toda una AZ          |
+------------------------------------------------------------+
```

---

## Pre-requisitos

- **Lab HA-02 completado.** El ASG `cloudcuyo-api-asg` debe estar corriendo con exactamente **2 instancias en estado `Healthy`** en el Target Group.
- El stack `cloudcuyo-ha-traffic-gen` debe estar desplegado (o ser re-desplegable).
- Region: **us-east-1**

**Verificar estado inicial antes de comenzar:**

> **¿Por que verificar que el ASG tenga exactamente HealthCheckType=EC2?** El experimento del Lab HA-03 depende de empezar en el estado "antes" (EC2 health check) para demostrar el problema. Si alguien cambio el health check a ELB durante el Lab HA-02, el Experimento 1 no funcionara como se espera: el ASG ya reemplazara la instancia automaticamente y no se podra observar el comportamiento problematico.

1. **EC2 > Auto Scaling Groups > cloudcuyo-api-asg > Instance management**
   - Deben aparecer 2 instancias en estado `InService`
2. **EC2 > Target Groups > cloudcuyo-api-tg > Targets**
   - Deben aparecer 2 targets en estado `Healthy`
3. **EC2 > Auto Scaling Groups > cloudcuyo-api-asg > Details > Health checks**
   - Debe mostrar `EC2` (no ELB todavia)

Resultado esperado: `HealthCheckType=EC2`, `Desired=2`, `InService=2`.

**Si el ASG no esta corriendo:**

1. Ir a **EC2 > Auto Scaling Groups**
2. Si `cloudcuyo-api-asg` no aparece en la lista, completar el Lab HA-02 primero

> **Antes de comenzar:** Tener a mano el DNS name del ALB (EC2 > Load Balancers > cloudcuyo-api-alb) y el Instance ID del traffic generator (CloudFormation > Stacks > cloudcuyo-ha-traffic-gen > Outputs).

---

## Fase 1: Entender el estado inicial — EC2 health check

Antes de hacer ningun experimento, conviene entender exactamente que hace (y que NO hace) el health check de EC2.

### 1.1 Que verifica el EC2 health check

El EC2 health check tiene dos componentes:

1. **EC2 system status check:** verifica que el hardware subyacente de AWS funcione correctamente (red fisica, energia, etc.)
2. **EC2 instance status check:** verifica que el sistema operativo de la instancia responda

**Lo que NO verifica:**
- Que la aplicacion este corriendo
- Que el puerto 5000 este escuchando
- Que `/health` responda con 200

Esto significa que si `gunicorn` se cae (proceso muerto, OOM killer, excepcion no capturada), el EC2 health check seguira reportando la instancia como sana.

> **¿Cual es la diferencia entre EC2 system status check y EC2 instance status check?** El system status check verifica que el hardware subyacente de AWS funcione (red fisica, energia). Si falla, el problema esta del lado de AWS y generalmente se resuelve solo o requiere migrar la instancia. El instance status check verifica que el sistema operativo de la instancia responda (kernel, networking interno). Si falla, generalmente requiere intervencion del usuario (reboot, reparacion del OS). Ninguno de los dos verifica que la APLICACION funcione.

### 1.2 Verificar la configuracion actual en consola

1. Ir a **EC2 > Auto Scaling Groups > cloudcuyo-api-asg**
2. Pestana **Details** → seccion **Health checks**
3. Confirmar:
   - **Health check type:** `EC2`
   - **Health check grace period:** `120 seconds`

### 1.3 Identificar los nodos del ASG

Anotar los IDs y las IPs privadas de las 2 instancias activas. Se necesitan en los experimentos siguientes.

1. Ir a **EC2 > Instances**
2. En el campo de busqueda, filtrar por tag: Key = `aws:autoscaling:groupName`, Value = `cloudcuyo-api-asg`
3. Anotar el **Instance ID** y la **IP privada** de cada instancia (columna **Private IPv4 address**)

Registrar los valores:

- **Nodo 1:** Instance ID `i-xxxxxxxxx`, IP privada `10.0.x.x`
- **Nodo 2:** Instance ID `i-xxxxxxxxx`, IP privada `10.0.x.x`

---

## Fase 2: Experimento 1 — Falla de proceso sin ELB health check

En este experimento se mata el proceso `gunicorn` en uno de los nodos. Se observa que el ALB detecta la falla y deja de enviarle trafico, pero el ASG NO reacciona porque usa solo EC2 health checks.

### 2.1 Preparar monitoreo en tiempo real

Antes de matar el proceso, abrir dos pestanas del navegador:

**Pestana 1 — monitorear estado del Target Group:**

1. Ir a **EC2 > Target Groups > cloudcuyo-api-tg > Targets**
2. Dejar esta pestana abierta y refrescar manualmente cada 15 segundos durante el experimento

**Pestana 2 — monitorear el ALB:**

1. Abrir `http://<DNS-del-ALB>/health` en el navegador
2. Refrescar cada 3-5 segundos y observar el campo `node` en la respuesta JSON

### 2.2 Matar el proceso gunicorn via SSM

> **¿Por que conectarse al nodo via SSM y no directamente via el traffic generator?** En el Lab HA-03, el traffic generator tiene acceso directo a los nodos (regla en el SG de los nodos). Para el experimento del crash, usamos SSM directamente al nodo porque es mas claro pedagogicamente: "entro a la instancia y mato el proceso". En produccion, una falla real seria mas parecida a lo que simula el endpoint `/api/v1/crash` (proceso que se cae por si solo), que se puede probar desde el traffic generator en el experimento alternativo.

1. Ir a **Systems Manager > Session Manager > Start session**
2. Seleccionar el Nodo 1 del ASG (Instance ID anotado en 1.3)
3. Click **Start session**

Dentro de la sesion SSM, ejecutar:

```bash
# Ver el proceso gunicorn corriendo
ps aux | grep gunicorn

# Detener el servicio (simula un crash real del proceso)
sudo systemctl stop cloudcuyo-api

# Confirmar que el proceso se detuvo
ps aux | grep gunicorn
# No deben aparecer procesos de gunicorn

# Verificar que el puerto 5000 ya no escucha
ss -tlnp | grep 5000
# No debe aparecer nada en el puerto 5000
```

> **¿Por que `systemctl stop` y no `kill -9`?** `systemctl stop` envia SIGTERM al proceso, que es la senal estandar de "terminacion ordenada". `kill -9` envia SIGKILL, que es forzoso e inmediato. En produccion, los crashes reales suelen ser mas parecidos a SIGKILL (OOM killer, SIGSEGV). Para el experimento, ambos producen el mismo resultado observable: el puerto 5000 deja de responder y el ALB marca el target como Unhealthy.

### 2.3 Observar lo que pasa

Volver a las **Pestanas 1 y 2** del navegador y observar la secuencia:

**Linea de tiempo esperada:**

| Tiempo | ALB health check | ASG activity | Browser /health |
|---|---|---|---|
| T+0s | Proceso muerto en node-1 | Sin cambios | Sigue respondiendo (va a node-2) |
| T+15s | Primer health check falla para node-1 | Sin cambios | Sin interrupciones |
| T+30s | Segundo health check falla, node-1 → `Unhealthy` | **Nada** | `node` siempre del nodo sano |
| T+60s+ | node-1 permanece `Unhealthy` | **Nada** | Solo un `node` en las respuestas |

**Observacion clave:** En **EC2 > Instances**, el nodo 1 sigue en estado `Running`. Para el ASG, la instancia esta perfectamente sana. La capacidad del grupo es 1 instancia activa en lugar de 2 deseadas.

**Verificar en consola:**

1. **EC2 > Auto Scaling Groups > cloudcuyo-api-asg > Instance management**
   - Ambas instancias siguen apareciendo como `InService` (el ASG cree que estan sanas)
2. **EC2 > Target Groups > cloudcuyo-api-tg > Targets**
   - Debe mostrar 1 `Healthy` y 1 `Unhealthy`

### 2.4 Implicacion del problema

Imaginar este escenario en produccion a las 3am:

- Un memory leak en la API hace que `gunicorn` sea matado por el OOM killer
- La instancia sigue Running desde el punto de vista de EC2
- El ASG no reacciona, la capacidad se reduce a la mitad
- Llega un pico de trafico inesperado y la instancia restante se satura
- El equipo de on-call recibe alertas de latencia alta, no de instancias caidas

Con ELB health checks (Fase 3), el ASG hubiera detectado el problema y lanzado un reemplazo automaticamente.

---

## Fase 3: Habilitar ELB health checks en el ASG

### 3.1 Cambiar la configuracion de health checks (AWS Console)

1. Ir a **EC2 > Auto Scaling Groups > cloudcuyo-api-asg**
2. Pestana **Details** → seccion **Health checks**
3. Click **Edit**
4. Cambiar **Health check type** de `EC2` a `EC2 and ELB`
5. Mantener **Health check grace period:** `120` segundos
6. Click **Update**

### 3.2 Que significa este cambio

Con `EC2 and ELB` activado, el ASG ahora toma decisiones de reemplazo basandose en **ambas** fuentes:

- Si EC2 reporta la instancia como unhealthy → el ASG la reemplaza
- Si el ALB reporta la instancia como Unhealthy → el ASG **tambien** la reemplaza

El health check grace period de 120 segundos sigue siendo valido: instancias recien lanzadas no son evaluadas por el health check ELB durante los primeros 120 segundos, para que tengan tiempo de arrancar.

> **¿Por que el cambio no es instantaneo?** Al cambiar a `EC2 and ELB`, el ASG no evalua el estado inmediatamente. Espera el proximo ciclo de evaluacion de health checks, que puede demorar 1-3 minutos. Durante ese tiempo, la instancia que fallo en el Experimento 1 sigue apareciendo como `InService` en el ASG aunque el Target Group la muestre como `Unhealthy`.

> **¿Por que mantener el grace period en 120s despues del cambio?** El grace period protege tanto las instancias existentes como las nuevas. Si lo bajamos a 0, el ASG podria evaluar una instancia que acaba de lanzarse y todavia esta en bootstrap. Mantenerlo en 120s es la configuracion correcta para produccion.

---

## Fase 4: Experimento 2 — Falla de proceso con ELB health check habilitado

El nodo 1 del Experimento 1 todavia esta `Unhealthy` en el Target Group (el proceso gunicorn sigue detenido). Con ELB health checks habilitados, el ASG ahora deberia detectarlo y lanzar un reemplazo.

### 4.1 Observar el reemplazo automatico

Despues de habilitar ELB health checks (Fase 3), el ASG reconcilia el estado en el siguiente ciclo de evaluacion. No es instantaneo: el ASG evalua el estado de ELB periodicamente.

**Monitorear en consola:**

1. **EC2 > Auto Scaling Groups > cloudcuyo-api-asg > Activity**
2. Refrescar la pagina cada 30 segundos y esperar (puede tomar 1-3 minutos) los eventos:
   - `Terminating EC2 instance: i-xxxxxxxxx. Reason: Instance failed ELB health checks.`
   - `Launching a new EC2 instance: i-xxxxxxxxx`

**Secuencia esperada:**

| Tiempo | ASG InService | TG Healthy | Evento |
|---|---|---|---|
| T+0 (post Fase 3) | 2 | 1 | ELB health check habilitado |
| T+1-3 min | 1-2 | 1 | ASG marca la instancia Unhealthy y empieza el reemplazo |
| T+1-3 min | 2 | 1 | ASG lanza una nueva instancia |
| T+3-5 min | 2 | 1-2 | Nueva instancia arranca; puede aparecer `Initial` o `Unhealthy` durante bootstrap |
| T+5-6 min | 2 | 2 | Nueva instancia pasa health check, queda `Healthy` |
| T+5 min aprox. | 2 | 2 | El target viejo puede seguir `draining` hasta que termine el deregistration delay |

Verificar el progreso en:
- **EC2 > Auto Scaling Groups > cloudcuyo-api-asg > Instance management** (refrescar cada 30s)
- **EC2 > Target Groups > cloudcuyo-api-tg > Targets** (refrescar cada 30s)

### 4.2 Verificar el reemplazo

Una vez que el ciclo completa:

1. Ir a **EC2 > Auto Scaling Groups > cloudcuyo-api-asg > Instance management**
   - El nodo que se rompio debe tener un Instance ID nuevo
   - El nodo que permanecio sano puede conservar el mismo Instance ID
   - Ambas instancias deben estar `InService`
2. Ir a **EC2 > Target Groups > cloudcuyo-api-tg > Targets**
   - Ambos targets deben estar `Healthy`

### 4.3 Crash del segundo nodo (repetir el experimento)

Para confirmar que el comportamiento es consistente, repetir el experimento con el segundo nodo:

1. Ir a **Systems Manager > Session Manager > Start session**
2. Seleccionar el Nodo 2 del ASG (Instance ID anotado en 1.3 — o el nuevo Instance ID del reemplazo)
3. Click **Start session**

Dentro de SSM:

```bash
sudo systemctl stop cloudcuyo-api
```

4. Observar en **EC2 > Target Groups > cloudcuyo-api-tg > Targets** que el ALB lo marca Unhealthy
5. Observar en **EC2 > Auto Scaling Groups > cloudcuyo-api-asg > Activity** que el ASG lo reemplaza automaticamente (sin intervencion manual)

### Troubleshooting de la Fase 4

| Sintoma | Posible causa | Correccion |
|---|---|---|
| El ASG no reemplaza la instancia despues de 5 minutos | ELB health check no fue habilitado correctamente, o el Target Group todavia no marco el target como Unhealthy | Verificar que el ASG muestre `EC2 and ELB` y que el Target Group muestre el target `Unhealthy` |
| Nueva instancia queda en `Pending` por mas de 5 minutos | User-data falla en la nueva instancia | Conectarse via SSM a la nueva instancia y revisar `/var/log/user-data.log` |
| El browser muestra timeouts durante el reemplazo | Normal: hay un breve periodo con 1 instancia sana | El ALB draining protege de errores, pero puede haber latencia aumentada |

---

## Fase 5: Experimento 3 — Shallow vs Deep health check

### 5.1 Definiciones

**Shallow health check (`/health`):**
- Solo verifica que el proceso de la aplicacion este corriendo y responda HTTP 200
- No depende de ninguna dependencia externa (base de datos, APIs de terceros, etc.)
- Rapido (responde en milisegundos)
- Estable: solo falla si el proceso en si esta caido

**Deep health check (`/health/deep`):**
- Verifica el proceso Y simula verificar una o mas dependencias externas
- En la API de demo, `time.sleep(0.05)` simula una consulta a la base de datos
- En produccion real podria hacer `SELECT 1` a la DB o verificar una cola SQS

### 5.2 Cambiar el health check del Target Group a `/health/deep`

1. Ir a **EC2 > Target Groups > cloudcuyo-api-tg**
2. Pestana **Health checks** > Click **Edit**
3. Cambiar **Health check path** de `/health` a `/health/deep`
4. Click **Save changes**

### 5.3 Observar que el comportamiento es normal

1. Ir a **EC2 > Target Groups > cloudcuyo-api-tg > Targets**
2. Refrescar la pagina cada 15 segundos durante 1-2 minutos
3. Los targets deben seguir apareciendo como `Healthy`

En la API demo, `/health/deep` siempre retorna `{"status": "ok", "db": "simulated_ok"}`. Los targets deben seguir Healthy.

### 5.4 El problema del deep check en produccion real

La API demo siempre reporta la DB como ok porque es simulada. Pero consideremos que pasaria en un escenario real:

**Escenario hipotetico:** La base de datos RDS en `us-east-1a` tiene un problema de red (falla de AZ parcial). Solo las instancias en `us-east-1a` no pueden alcanzar la DB.

| Con shallow `/health` | Con deep `/health/deep` |
|---|---|
| Las instancias en AZ-A siguen respondiendo `/health` con 200 | Las instancias en AZ-A fallan `/health/deep` porque no alcanzan la DB |
| El ALB sigue enviando trafico a AZ-A | El ALB marca todos los nodos de AZ-A como Unhealthy |
| Usuarios en AZ-A reciben errores de DB en la respuesta | El ASG empieza a reemplazar los nodos de AZ-A |
| Un monitor de DB alerta sobre el problema real | Los nodos nuevos en AZ-A tampoco alcanzan la DB |
| El equipo interviene en el problema de red de la DB | Los nodos nuevos tambien fallan → loop de reemplazos en cascada |
| Los nodos en AZ-B siguen sanos y reciben trafico | Eventualmente el ASG agota el maximo de instancias |

**El deep check convirtio un problema de DB en un problema de instancias**. El ASG intento "arreglar" algo que no se podia arreglar reemplazando instancias.

> **¿Cuando SI conviene usar deep health check?** En arquitecturas donde la dependencia externa tiene alta disponibilidad independiente (ej: un cache Redis Multi-AZ, una base de datos RDS Multi-AZ con failover automatico). Si la dependencia puede fallar por si sola y hacer failover sin afectar a los nodos, el deep check puede detectar el problema antes. Pero si la dependencia puede fallar en toda una AZ al mismo tiempo que los nodos, el deep check causa el efecto cascada descrito en la tabla.

### 5.5 Tabla de trade-offs

| Criterio | Shallow `/health` | Deep `/health/deep` |
|---|---|---|
| Detecta proceso caido | Si | Si |
| Detecta falla de dependencia externa | No | Si |
| Riesgo de falso positivo | Bajo | Alto (si la dep falla en toda una AZ) |
| Riesgo de reemplazos en cascada | Ninguno | Alto si deps multi-AZ fallan juntas |
| Tiempo de respuesta del check | Muy rapido (~1ms) | Mas lento (depende de la dep) |
| Recomendado para ALB/ASG | Si | No, salvo que la dep sea altamente estable |
| Recomendado para monitoreo CloudWatch | Complementario | Si, para alertar sobre deps |

**Recomendacion de arquitectura:**

- Usar **`/health`** (shallow) para el health check del Target Group y del ASG
- Crear una **CloudWatch Alarm** separada que monitoree `/health/deep` periodicamente
- Si `/health/deep` falla, la alarma notifica al equipo sin generar reemplazos automaticos innecesarios

### 5.6 Restaurar el health check a shallow

1. Ir a **EC2 > Target Groups > cloudcuyo-api-tg**
2. Pestana **Health checks** > Click **Edit**
3. Cambiar **Health check path** de `/health/deep` a `/health`
4. Click **Save changes**
5. Verificar en la pestana **Targets** que los 2 targets siguen/vuelven a estado `Healthy`

---

## Fase 6: Dashboard de CloudWatch

Crear un dashboard basico para monitorear la salud del sistema. Esto es especialmente util para tener visibilidad en tiempo real durante experimentos o incidentes.

### 6.1 Verificar metricas de grupo del ASG

Antes de crear el dashboard, confirmar que el ASG publica metricas de grupo. Si no se habilitaron en HA-02, CloudWatch no mostrara `GroupDesiredCapacity` ni `GroupInServiceInstances`.

1. Ir a **EC2 > Auto Scaling Groups > cloudcuyo-api-asg**
2. Abrir la pestana **Monitoring**
3. Si aparece un boton como **Enable group metrics collection** o **Edit monitoring**, habilitar las metricas del grupo
4. Esperar 2-5 minutos para que las metricas aparezcan en CloudWatch

### 6.2 Crear el dashboard (AWS Console)

1. Ir a **CloudWatch > Dashboards > Create dashboard**
2. **Dashboard name:** `CloudCuyo-HA-Monitor`
3. Click **Create dashboard**
4. Seleccionar widget type: **Line** → **Next**

### 6.3 Agregar metrica HealthyHostCount

1. En el wizard de metricas, buscar `HealthyHostCount`
2. Navegar: **ApplicationELB > Per AppELB, per TG Metrics**
3. Buscar `cloudcuyo-api-tg` y seleccionar la metrica `HealthyHostCount`
4. Configurar:
   - **Period:** `1 minute`
   - **Statistic:** `Average`
5. Click **Create widget**

### 6.4 Agregar metrica UnhealthyHostCount

Repetir el proceso con `UnhealthyHostCount` del mismo Target Group.

### 6.5 Agregar metricas del ASG

Repetir para:
- **AutoScaling > GroupMetrics > GroupDesiredCapacity** del ASG `cloudcuyo-api-asg`
- **AutoScaling > GroupMetrics > GroupInServiceInstances** del mismo ASG

> Si estas metricas no aparecen, volver a la Fase 6.1 y confirmar que la recoleccion de metricas de grupo esta habilitada. Luego esperar unos minutos y refrescar el selector de metricas.

### 6.6 Reproducir el Experimento 1 con el dashboard visible

Para ver el dashboard en accion, repetir la secuencia del Experimento 1:

1. Conectarse via SSM a uno de los nodos del ASG (**Systems Manager > Session Manager > Start session**)
2. Ejecutar dentro de SSM:

```bash
sudo systemctl stop cloudcuyo-api
```

3. Observar en el dashboard en tiempo real:
   - `HealthyHostCount` cae de 2 a 1
   - `UnhealthyHostCount` sube de 0 a 1
   - `GroupInServiceInstances` sigue en 2 (hasta que el ASG reacciona con ELB health check habilitado)
   - Luego: `GroupInServiceInstances` cae a 1 transitoriamente mientras se lanza el reemplazo
   - Finalmente: `HealthyHostCount` vuelve a 2, `UnhealthyHostCount` vuelve a 0

Este es el comportamiento que un equipo de operaciones deberia monitorear en produccion.

---

## Limpieza completa

Al finalizar el modulo de Alta Disponibilidad, eliminar todos los recursos creados en los labs HA-01, HA-02 y HA-03.

### Paso 1: Eliminar el Traffic Generator

1. Ir a **CloudFormation > Stacks**
2. Seleccionar `cloudcuyo-ha-traffic-gen`
3. Click **Delete** > confirmar
4. Esperar a que el stack desaparezca de la lista

### Paso 2: Eliminar el Auto Scaling Group

1. Ir a **EC2 > Auto Scaling Groups**
2. Seleccionar `cloudcuyo-api-asg`
3. **Actions > Delete**
4. Escribir `delete` para confirmar
5. Click **Delete**
6. Esperar hasta que las instancias terminen (~2-3 minutos) — verificar en **EC2 > Instances** que las instancias del ASG desaparecen

### Paso 3: Eliminar el Launch Template

1. Ir a **EC2 > Launch Templates**
2. Seleccionar `cloudcuyo-api-lt`
3. **Actions > Delete template** → confirmar

### Paso 4: Eliminar ALB y Target Group

1. Ir a **EC2 > Load Balancers**
2. Seleccionar `cloudcuyo-api-alb` → **Actions > Delete load balancer** → confirmar
3. Esperar a que el ALB desaparezca de la lista (puede tardar 1-2 minutos)
4. Ir a **EC2 > Target Groups**
5. Seleccionar `cloudcuyo-api-tg` → **Actions > Delete** → confirmar

### Paso 5: Eliminar Security Groups

1. Ir a **EC2 > Security Groups**
2. Seleccionar `cloudcuyo-alb-sg` → **Actions > Delete security group** → confirmar
3. Seleccionar `cloudcuyo-api-node-sg` → **Actions > Delete security group** → confirmar
4. Si aparece error de dependencia al eliminar `cloudcuyo-alb-sg`, verificar que el ALB ya fue eliminado completamente antes de reintentar

### Paso 6: Eliminar el Dashboard de CloudWatch (opcional)

1. Ir a **CloudWatch > Dashboards**
2. Seleccionar `CloudCuyo-HA-Monitor`
3. **Actions > Delete** → confirmar

### NO eliminar (pre-requisitos persistentes reutilizables)

- VPC (`10.0.0.0/16`), subnets, Internet Gateway, route tables
- IAM Role SSM + Instance Profile
- Key pair `lab-key`

---

## Criterios de exito

- **Experimento 1:** Con EC2 health check, el ASG NO reemplaza la instancia cuyo proceso `gunicorn` se cayo. La instancia sigue en estado `Running` en EC2 pero `Unhealthy` en el Target Group.
- **Experimento 2:** Al habilitar ELB health check, el ASG detecta la instancia Unhealthy y la reemplaza automaticamente. Los 2 targets vuelven a estado `Healthy` sin intervencion manual.
- **Experimento 3:** El alumno puede explicar la diferencia entre shallow y deep health check y cuando usar cada uno.
- El browser contra el ALB no muestra interrupciones durante el reemplazo automatico de instancias.
- El Dashboard de CloudWatch muestra la caida y recuperacion de `HealthyHostCount` en tiempo real.

---

## Resumen del modulo de Alta Disponibilidad

Al completar los tres labs de este modulo, CloudCuyo paso de:

**Estado inicial (arquitectura de partida):**
- `api01`: servidor unico, SPOF
- `lb01`: NGINX en EC2, otro SPOF
- Capacidad fija, sin escalado automatico
- Sin monitoreo automatico de salud del proceso

**Estado final (Labs HA-01, HA-02, HA-03):**
- ALB administrado por AWS: sin SPOF en el balanceador
- 2+ nodos de API en distintas Availability Zones
- Auto Scaling Group: capacidad se ajusta automaticamente a la carga
- ELB health checks: reemplazo automatico ante fallas de proceso
- CloudWatch dashboard: visibilidad en tiempo real del estado del sistema
