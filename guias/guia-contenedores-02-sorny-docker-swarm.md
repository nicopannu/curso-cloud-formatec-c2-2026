# Guia B1: Sorny — migrar servicios a Docker Swarm en EC2

**Objetivo:** partir de Sorny con ALB y frontend en EC2, crear un cluster Docker Swarm con 1 EC2 manager y 2 EC2 workers publicos y migrar dos APIs (`purchase-service` y `payment-service`) a servicios contenedorizados. La administracion se realiza desde AWS Console y conexiones SSM Session Manager.

**Duracion estimada:** 2.5 a 3 horas

**Modulo:** Modulo 2 — Clase 4: Contenedores y Serverless

---

## Contexto narrativo

Sorny ya paso por una primera separacion de responsabilidades. Ahora el equipo quiere avanzar un paso mas: empaquetar servicios como imagenes Docker y ejecutarlos como servicios replicados.

La decision de arquitectura de esta guia no es “usar Docker porque si”. La pregunta es:

```text
Que cambia cuando una API deja de correr como proceso instalado en una VM y pasa a correr como servicio contenedorizado en un cluster con plano de control y dos nodos de ejecucion?
```

Para mantener una arquitectura visible y facil de discutir en clase, conservamos:

- un ALB publico como punto de entrada;
- el frontend en su propia EC2;
- health checks y reglas por path;
- acceso administrativo por SSM, no por SSH.

Cambiamos:

- `purchase-service` pasa a Docker Swarm;
- `payment-service` pasa a Docker Swarm;
- `delivery-service` no se migra a Swarm: queda reservado para la guia B2 en Lambda.

---

## Arquitectura inicial del lab

Bootstrap:

```text
cloudformation/sorny-swarm-m2c4-bootstrap.yaml
```

El stack crea:

```text
Usuario
  |
  v
ALB publico
  |
  +-- /*                               -> frontend EC2 publica :5000
  +-- /api/purchases, /api/purchases/* -> target group purchase-swarm :5003
  +-- /api/payments,  /api/payments/*  -> target group payment-swarm :5004

EC2 publicas con SSM:
  - frontend
  - swarm-manager
  - swarm-worker-1
  - swarm-worker-2
```

Todas las EC2 tienen IP publica para facilitar la identificacion en consola y la demostracion en clase. La administracion se hace por SSM Session Manager.

---

## Arquitectura objetivo

```text
Usuario
  |
  v
ALB publico
  |
  +-- /*                               -> frontend EC2
  |
  +-- /api/purchases/*                 -> Swarm routing mesh puerto 5003
  |                                         replicas purchase-service
  |                                         contenedores distribuidos en 2 workers
  |
  +-- /api/payments/*                  -> Swarm routing mesh puerto 5004
                                            replicas payment-service
                                            contenedores distribuidos en 2 workers

Docker Swarm:
  swarm-manager EC2 publica
  swarm-worker-1 EC2 publica
  swarm-worker-2 EC2 publica

Guia B2:
  /api/delivery -> Lambda
```

Punto importante: el ALB sigue siendo el frente unico para la aplicacion web. Docker Swarm no reemplaza al ALB; Swarm administra contenedores dentro del cluster.

---

## Objetivos de aprendizaje

Al finalizar, deberias poder:

- explicar la diferencia entre imagen, contenedor, servicio Swarm y stack;
- crear un cluster Docker Swarm con 1 manager y 2 workers usando EC2;
- desplegar `purchase-service` y `payment-service` como servicios replicados;
- entender el routing mesh de Swarm y su relacion con el ALB;
- validar health checks desde el ALB y desde cada nodo;
- observar como Swarm reubica tareas ante fallas simples;
- distinguir que parte administra AWS y que parte administra el equipo;
- preparar el terreno para mover `delivery-service` a Lambda en la siguiente guia.

---

## Alcance del lab

### Obligatorio

- Crear stack base con CloudFormation desde AWS Console.
- Entrar por SSM al manager y a los dos workers de Swarm.
- Inicializar Swarm en el manager.
- Unir los dos workers al cluster.
- Construir imagenes de `purchase-service` y `payment-service`.
- Desplegar un stack Swarm con 2 replicas por servicio.
- Probar el flujo por ALB.
- Revisar health checks y logs.

### Fuera de alcance para esta clase

- Docker Registry privado productivo.
- TLS interno entre servicios.
- Secrets Manager.
- Autoscaling automatico de nodos.
- Blue/green o canary deploy.
- Persistencia de datos.

---

## Pre-requisitos

- Haber completado Guia A o entender Dockerfile, imagen y contenedor.
- Acceso a AWS Console en la region del curso.
- VPC con 2 subnets publicas.
- Instance Profile existente con permisos para SSM.
- Permisos para crear CloudFormation, EC2, ALB, Security Groups y CloudWatch Logs.
- Repositorio del curso disponible en la VM manager, o posibilidad de copiar los archivos desde el repo local.

No ejecutar recursos AWS si el docente no habilito la fase practica.

---

## Fase 1: Crear el bootstrap desde CloudFormation Console

1. Ir a:

```text
CloudFormation > Stacks > Create stack > With new resources
```

2. Seleccionar:

```text
Upload a template file
```

3. Cargar:

```text
cloudformation/sorny-swarm-m2c4-bootstrap.yaml
```

4. Stack name sugerido:

```text
sorny-m2c4-swarm
```

5. Parametros sugeridos:

| Parametro | Valor |
|---|---|
| `VpcId` | VPC del laboratorio |
| `SubnetAId` | Subnet publica A |
| `SubnetBId` | Subnet publica B |
| `InstanceType` | `t3.micro` o `t3.small` |
| `SsmInstanceProfileName` | Instance Profile SSM del curso |
| `ProjectName` | `sorny` |
| `Environment` | `m2-c4-swarm` |

6. Crear stack.

7. Esperar estado:

```text
CREATE_COMPLETE
```

8. En la solapa **Outputs**, anotar:

| Output | Uso |
|---|---|
| `AlbDnsName` | URL publica principal |
| `FrontendPublicIp` | identificacion de VM frontend |
| `SwarmManagerInstanceId` | conexion SSM al manager |
| `SwarmManagerPublicIp` | IP publica del manager |
| `SwarmWorker1InstanceId` | conexion SSM al worker 1 |
| `SwarmWorker1PublicIp` | IP publica del worker 1 |
| `SwarmWorker2InstanceId` | conexion SSM al worker 2 |
| `SwarmWorker2PublicIp` | IP publica del worker 2 |
| `PurchaseTargetGroupName` | validar targets para purchases |
| `PaymentTargetGroupName` | validar targets para payments |

---

## Fase 2: Validar frontend y nodos

Abrir en navegador:

```text
http://<AlbDnsName>/
```

Resultado esperado:

- pagina simple de Sorny;
- datos del backend frontend;
- recordatorio de rutas API.

Probar health checks aun antes de desplegar Swarm:

```text
http://<AlbDnsName>/api/purchases/health
http://<AlbDnsName>/api/payments/health
```

Es normal que respondan error mientras los servicios Swarm no esten levantados. El ALB ya tiene reglas y target groups; falta que haya contenedores escuchando en los puertos publicados.

Checkpoint para clase:

```text
El ALB puede estar creado correctamente y aun asi devolver error si el runtime de la aplicacion no esta listo.
```

---

## Fase 3: Conectarse por SSM al manager

1. Ir a:

```text
EC2 > Instances
```

2. Seleccionar la instancia con nombre:

```text
sorny-swarm-manager-m2-c4-swarm
```

3. Click:

```text
Connect > Session Manager > Connect
```

4. Elevar a root o usar sudo:

```bash
sudo -i
```

5. Validar Docker:

```bash
docker --version
systemctl status docker --no-pager
```

Resultado esperado:

```text
Docker version ...
Active: active (running)
```

---

## Fase 4: Inicializar Docker Swarm

En el manager, obtener la IP privada:

```bash
MANAGER_PRIVATE_IP=$(curl -s http://169.254.169.254/latest/meta-data/local-ipv4)
echo $MANAGER_PRIVATE_IP
```

Inicializar Swarm:

```bash
docker swarm init --advertise-addr $MANAGER_PRIVATE_IP
```

La salida incluye un comando similar a:

```bash
docker swarm join --token SWMTKN-... <manager-private-ip>:2377
```

Copiar ese comando. Se usara en el worker.

Validar:

```bash
docker node ls
```

Resultado esperado:

```text
HOSTNAME              STATUS    AVAILABILITY   MANAGER STATUS
...manager...         Ready     Active         Leader
```

Como en este lab queremos que el manager no reciba trafico ni ejecute APIs, dejarlo en modo `Drain`:

```bash
MANAGER_NODE=$(docker node ls --format '{{.Hostname}} {{.ManagerStatus}}' | awk '$2 == "Leader" {print $1}')
docker node update --availability drain "$MANAGER_NODE"
docker node ls
```

Resultado esperado:

```text
...manager...         Ready     Drain          Leader
```

Decision tecnica:

```text
El manager administra el cluster.
Los workers ejecutan workloads de aplicacion.
El ALB apunta solo a workers.
```

---

## Fase 5: Unir los dos workers al cluster

1. Abrir otra Session Manager hacia:

```text
sorny-swarm-worker-1-m2-c4-swarm
sorny-swarm-worker-2-m2-c4-swarm
```

2. Ejecutar:

```bash
sudo -i
docker --version
```

3. Pegar el comando `docker swarm join` obtenido en el manager.

4. Repetir el mismo procedimiento en el segundo worker.

5. Volver al manager y validar:

```bash
docker node ls
```

Resultado esperado:

```text
manager    Ready   Drain    Leader
worker-1   Ready   Active
worker-2   Ready   Active
```

Checkpoint:

- El manager decide donde corren las tareas.
- El manager coordina el cluster.
- Los workers ejecutan contenedores de aplicacion.
- En este lab el ALB apunta solo a los workers.
- El manager se deja en `Drain` para no mezclar plano de control y plano de datos.

---

## Fase 6: Cargar artefactos de Sorny en el manager

La forma mas simple para la clase es crear los archivos en el manager copiando desde el repo. El repo trae:

```text
apps/sorny-swarm/
  docker-stack.yml
  purchase-service/
    app.py
    requirements.txt
    Dockerfile
  payment-service/
    app.py
    requirements.txt
    Dockerfile
```

Si el repo esta disponible en la VM:

```bash
cd /home/ec2-user/curso-cloud-formatec-c2-2026/apps/sorny-swarm
```

Si no esta disponible, crear una carpeta y copiar los archivos desde la guia/repo del docente:

```bash
mkdir -p /opt/sorny-swarm
cd /opt/sorny-swarm
```

Decision tecnica:

```text
Para un lab simple, construimos imagenes localmente en los workers.
En produccion usariamos un registry como ECR para que cualquier worker pueda descargar la imagen.
```

---

## Fase 7: Construir imagenes en el manager

En el manager:

```bash
cd /opt/sorny-swarm
# o la ruta donde esten los archivos

docker build -t sorny/payment-service:swarm-v1 ./payment-service
docker build -t sorny/purchase-service:swarm-v1 ./purchase-service
```

Validar:

```bash
docker image ls | grep sorny
```

Resultado esperado:

```text
sorny/payment-service    swarm-v1
sorny/purchase-service   swarm-v1
```

---

## Fase 8: Construir imagenes en los dos workers sin registry

Como no usamos ECR en este lab, los dos workers deben tener las mismas imagenes locales. El manager puede construirlas para prueba, pero los workloads van a quedar en los workers porque el manager estara en `Drain`.

En el manager:

```bash
cd /opt/sorny-swarm
mkdir -p /tmp/sorny-images

docker save sorny/payment-service:swarm-v1 -o /tmp/sorny-images/payment-service.tar
docker save sorny/purchase-service:swarm-v1 -o /tmp/sorny-images/purchase-service.tar
```

Opcion simple para clase:

1. Abrir SSM en el worker.
2. Crear tambien `/opt/sorny-swarm`.
3. Copiar los mismos archivos y construir imagenes con los mismos comandos.

En cada worker:

```bash
cd /opt/sorny-swarm

docker build -t sorny/payment-service:swarm-v1 ./payment-service
docker build -t sorny/purchase-service:swarm-v1 ./purchase-service
```

> Nota docente: esta duplicacion es intencional. Sirve para explicar por que en un entorno real se usa un registry. Swarm necesita que cada nodo pueda resolver la imagen indicada en el stack.

---

## Fase 9: Desplegar stack Swarm

En el manager, revisar `docker-stack.yml`:

```bash
cat docker-stack.yml
```

Debe declarar dos servicios:

```text
payment-service  replicas: 2  published port: 5004  placement: node.role == worker
purchase-service replicas: 2  published port: 5003  placement: node.role == worker
```

La restriccion `node.role == worker` evita que las APIs se ejecuten en el manager. Ademas, en la fase anterior dejamos el manager en `Drain` para reforzar la separacion entre plano de control y plano de datos.

Desplegar:

```bash
docker stack deploy -c docker-stack.yml sorny
```

Validar servicios:

```bash
docker service ls
docker stack ps sorny
```

Resultado esperado:

```text
sorny_payment-service    replicated   2/2
sorny_purchase-service   replicated   2/2
```

Validar que las tareas quedaron en workers y no en el manager:

```bash
docker stack ps sorny
```

Si alguna task aparece en el manager, revisar que el manager este en `Drain`:

```bash
docker node ls
```

Si alguna tarea queda en `Rejected` o `Preparing`, revisar:

```bash
docker service ps sorny_payment-service --no-trunc
docker service ps sorny_purchase-service --no-trunc
```

Causa comun:

```text
No such image: sorny/...:swarm-v1
```

Solucion: construir la imagen en el nodo donde Swarm intento ejecutar la tarea, o usar un registry.

---

## Fase 10: Probar desde cada nodo

En manager:

```bash
curl -s http://localhost:5004/api/payments/health
curl -s http://localhost:5003/api/purchases/health
```

En worker:

```bash
curl -s http://localhost:5004/api/payments/health
curl -s http://localhost:5003/api/purchases/health
```

Aunque el contenedor especifico no este corriendo en ese nodo, el routing mesh de Swarm puede recibir la conexion en el puerto publicado y enrutarla internamente.

Observar `hostname` e `ips` en la respuesta. Repetir varias veces:

```bash
for i in $(seq 1 5); do curl -s http://localhost:5003/api/purchases/health; echo; done
```

Pregunta de checkpoint:

```text
Por que no siempre responde el mismo hostname?
```

---

## Fase 11: Validar target groups en ALB

Ir a:

```text
EC2 > Target Groups
```

Abrir target group de purchases:

```text
sorny-purchase-swarm-...
```

Validar:

- targets: worker 1 y worker 2;
- puerto: 5003;
- health check path: `/api/purchases/health`;
- estado esperado: `healthy`.

Abrir target group de payments:

```text
sorny-payment-swarm-...
```

Validar:

- targets: worker 1 y worker 2;
- puerto: 5004;
- health check path: `/api/payments/health`;
- estado esperado: `healthy`.

Decision tecnica:

```text
El ALB balancea entre EC2s.
Swarm balancea/rutea entre contenedores dentro del cluster.
Hay dos capas de distribucion de trafico.
```

---

## Fase 12: Probar flujo por ALB

Health checks desde navegador o CloudShell:

```bash
curl http://<AlbDnsName>/api/payments/health
curl http://<AlbDnsName>/api/purchases/health
```

Crear compra:

```bash
curl -X POST http://<AlbDnsName>/api/purchases \
  -H 'Content-Type: application/json' \
  -d '{"product_name":"Sorny Luma 32","amount":189999}'
```

Resultado esperado:

```json
{
  "status": "purchase_created",
  "backend": "purchase-service",
  "runtime": "docker-swarm",
  "payment": {
    "backend": "payment-service",
    "runtime": "docker-swarm",
    "status": "payment_link_created"
  }
}
```

Checkpoint:

```text
El contrato HTTP se mantuvo, pero el runtime cambio.
El cliente sigue entrando por ALB.
```

---

## Fase 13: Simular falla simple

En el manager, ver contenedores:

```bash
docker ps
```

Elegir un contenedor de `purchase-service` y detenerlo:

```bash
docker stop <container_id>
```

Validar:

```bash
docker service ps sorny_purchase-service
```

Resultado esperado:

- una tarea aparece como terminada;
- Swarm crea otra tarea para volver a `2/2`.

Probar nuevamente:

```bash
curl http://<AlbDnsName>/api/purchases/health
```

Discusion:

- Docker Engine solo no recrea servicios replicados.
- Swarm agrega control deseado: quiero 2 replicas.
- ALB no sabe de replicas individuales; solo sabe si los nodos responden por el puerto publicado.

---

## Fase 14: Observabilidad basica

Ver logs de servicios:

```bash
docker service logs sorny_purchase-service --tail 50
docker service logs sorny_payment-service --tail 50
```

Ver distribucion de tareas:

```bash
docker stack ps sorny
```

Ver uso local:

```bash
docker stats --no-stream
```

En AWS Console:

```text
EC2 > Target Groups > Targets
EC2 > Load Balancers > Monitoring
```

Preguntas:

- Que ve CloudWatch/ALB?
- Que ve Docker Swarm?
- Donde buscarias si `/api/purchases` responde 502?

---

## Fase 15: Preparar el paso a Lambda

En esta guia migramos dos servicios a contenedores:

```text
purchase-service -> Docker Swarm
payment-service  -> Docker Swarm
```

No migramos `delivery-service` a Swarm. Lo dejamos para la guia B2:

```text
delivery-service -> AWS Lambda
```

Motivo arquitectonico:

- purchases y payments se comportan como APIs de servicio, con replicas y llamadas internas;
- delivery/contacto es una accion corta, stateless y orientada a evento HTTP;
- esto permite comparar contenedores vs serverless sin mezclar ambos modelos en el mismo paso.

---

## Troubleshooting

### El worker no se une al cluster

Revisar Security Group entre nodos:

- TCP 2377;
- TCP/UDP 7946;
- UDP 4789.

Validar que se use IP privada del manager en `docker swarm join`.

### El servicio queda en 1/2 o 0/2

Revisar:

```bash
docker service ps <servicio> --no-trunc
```

Causa frecuente:

```text
La imagen existe en el manager o en un worker, pero no en el worker donde Swarm intento ejecutar la tarea.
```

### ALB marca targets unhealthy

Revisar:

- servicio Swarm publicado en puerto correcto;
- SG permite ALB -> nodos en 5003/5004;
- health path correcto;
- contenedores corriendo.

### `/api/purchases` crea compra pero payment falla

Revisar variable:

```bash
docker service inspect sorny_purchase-service --pretty
```

Debe existir:

```text
PAYMENT_URL=http://payment-service:5004/api/payments/checkout
```

Dentro de la red overlay, `payment-service` resuelve por DNS interno de Swarm.

---

## Limpieza

Desde el manager:

```bash
docker stack rm sorny
```

Esperar a que desaparezcan servicios:

```bash
docker service ls
```

Luego en AWS Console:

```text
CloudFormation > Stacks > sorny-m2c4-swarm > Delete
```

Verificar que se eliminen:

- ALB;
- Target Groups;
- EC2 frontend;
- EC2 swarm manager;
- EC2 swarm worker 1;
- EC2 swarm worker 2;
- Security Groups.

---

## Entregables

Cada grupo debe entregar:

1. Captura o texto de `docker node ls` con manager en `Ready/Drain` y dos workers en `Ready/Active`.
2. Captura o texto de `docker service ls` mostrando `2/2` replicas para los dos servicios.
3. Evidencia de health checks por ALB:
   - `/api/purchases/health`
   - `/api/payments/health`
4. Respuesta JSON de una compra creada por `/api/purchases` incluyendo respuesta de payment.
5. Explicacion breve: que hace el ALB y que hace Docker Swarm.
6. Un problema encontrado y como lo diagnosticaron.

---

## Criterios de evaluacion

| Criterio | Excelente | Suficiente | A revisar |
|---|---|---|---|
| Cluster Swarm | Manager en Drain y 2 workers Ready/Active, roles claros | Cluster funciona con ayuda | No se forma cluster |
| Servicios | 2 servicios con 2 replicas y health OK | Servicios levantan pero con dudas | No hay servicios estables |
| Integracion ALB | Rutas `/api/purchases` y `/api/payments` funcionan | Health OK pero flujo incompleto | ALB no llega a servicios |
| Razonamiento | Explica ALB vs Swarm, replicas y routing mesh | Describe pasos pero con poca decision | Solo ejecuta comandos |
| Diagnostico | Usa `docker service ps`, logs y Target Groups | Revisa parcialmente | No logra aislar fallas |
| Limpieza | Elimina recursos correctamente | Limpia con asistencia | Deja recursos corriendo |

---

## Cierre para discusion

Preguntas para cerrar:

1. Que problema resuelve Swarm que no resolvia `docker run`?
2. Por que el ALB no alcanza como orquestador de contenedores?
3. Que riesgos aparecen al administrar nosotros las EC2 del cluster?
4. Por que en produccion convendria usar un registry en vez de construir imagenes nodo por nodo?
5. Que tipo de servicio de Sorny migrarias a Lambda en vez de Swarm?

Mensaje final:

```text
Contenedores no son solo empaquetado. Cuando hay replicas, scheduling, health y recuperacion ante falla, aparece la necesidad de orquestacion. En este lab esa orquestacion la aporta Docker Swarm; el ALB sigue siendo el frente HTTP de Sorny.
```
