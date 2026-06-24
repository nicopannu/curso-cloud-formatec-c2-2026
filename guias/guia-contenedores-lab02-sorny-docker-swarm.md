# Guia Contenedores LAB02: Sorny — migrar servicios a Docker Swarm en EC2

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
- `delivery-service` no se migra a Swarm: queda reservado para el LAB03 en Lambda.

---

## Arquitectura inicial del lab

Bootstrap:

```text
cloudformation/contenedores-lab02-sorny-swarm-bootstrap.yaml
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
  +-- /api/purchases/*                 -> workers Swarm puerto 5003
  |                                         replicas purchase-service
  |                                         contenedores distribuidos en 2 workers
  |
  +-- /api/payments/*                  -> workers Swarm puerto 5004
                                            replicas payment-service
                                            contenedores distribuidos en 2 workers

Docker Swarm:
  swarm-manager EC2 publica
  swarm-worker-1 EC2 publica
  swarm-worker-2 EC2 publica

LAB03:
  /api/delivery -> Lambda
```

Punto importante: el ALB sigue siendo el frente unico para la aplicacion web. Docker Swarm no reemplaza al ALB; Swarm administra contenedores dentro del cluster.

---

## Objetivos de aprendizaje

Al finalizar, deberias poder:

- explicar la diferencia entre imagen, contenedor, servicio Swarm y stack;
- crear un cluster Docker Swarm con 1 manager y 2 workers usando EC2;
- desplegar `purchase-service` y `payment-service` como servicios replicados;
- entender como publicar puertos en Swarm para que un ALB apunte a workers reales;
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

- Haber completado LAB01 o entender Dockerfile, imagen y contenedor.
- Acceso a AWS Console en la region del curso.
- VPC con 2 subnets publicas.
- Instance Profile existente con permisos para SSM.
- Permisos para crear CloudFormation, EC2, ALB, Security Groups y CloudWatch Logs.
- Acceso a internet desde las EC2 para descargar el paquete del lab desde la branch `m2-c4` del repositorio.

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
cloudformation/contenedores-lab02-sorny-swarm-bootstrap.yaml
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

5. Validar Docker. Igual que en la guia anterior, `CREATE_COMPLETE` no siempre significa que el `UserData` termino de instalar Docker. Esperar explicitamente:

```bash
while ! command -v docker >/dev/null 2>&1; do
  echo "Esperando instalacion de Docker por UserData..."
  sleep 10
done

while ! systemctl is-active --quiet docker; do
  echo "Esperando que el daemon Docker quede activo..."
  sleep 10
done

docker --version
systemctl status docker --no-pager
```

Resultado esperado:

```text
Docker version ...
Active: active (running)
```

Si Docker no aparece despues de varios minutos, revisar `/var/log/cloud-init-output.log`.

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

while ! command -v docker >/dev/null 2>&1; do
  echo "Esperando instalacion de Docker por UserData..."
  sleep 10
done

while ! systemctl is-active --quiet docker; do
  echo "Esperando que el daemon Docker quede activo..."
  sleep 10
done

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

## Fase 6: Descargar artefactos de Sorny en el manager

No vamos a crear `Dockerfile`, `app.py` ni `docker-stack.yml` copiando texto desde la guia. Esos archivos son parte del codigo fuente del curso y se descargan como un paquete versionado desde la branch `m2-c4`.

En el manager:

```bash
LAB_DIR="$HOME/m2-c4-lab"
mkdir -p "$LAB_DIR"
cd "$LAB_DIR"
rm -rf curso-cloud-formatec-c2-2026-m2-c4 m2-c4.tar.gz

curl -L -o m2-c4.tar.gz \
  https://github.com/nicopannu/curso-cloud-formatec-c2-2026/archive/refs/heads/m2-c4.tar.gz

tar xzf m2-c4.tar.gz

cd curso-cloud-formatec-c2-2026-m2-c4/apps/sorny-swarm
ls -R
```

El directorio debe contener:

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

Decision tecnica:

```text
No copiamos archivos a mano porque rompe trazabilidad y genera errores.
El Dockerfile y el codigo viajan juntos, versionados en la branch del lab.
Para un lab simple, construimos imagenes localmente en cada nodo.
En produccion usariamos CI/CD + ECR para que cualquier worker descargue la imagen.
```

---

## Fase 7: Construir imagenes en el manager

En el manager:

```bash
cd "$HOME/m2-c4-lab/curso-cloud-formatec-c2-2026-m2-c4/apps/sorny-swarm"

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

## Fase 8: Descargar artefactos y construir imagenes en los dos workers sin registry

Como no usamos ECR en este lab, cada worker debe tener las mismas imagenes locales que declara `docker-stack.yml`. El manager puede construirlas para inspeccion, pero los workloads van a quedar en los workers porque el manager estara en `Drain`.

En cada worker, repetir:

```bash
LAB_DIR="$HOME/m2-c4-lab"
mkdir -p "$LAB_DIR"
cd "$LAB_DIR"
rm -rf curso-cloud-formatec-c2-2026-m2-c4 m2-c4.tar.gz

curl -L -o m2-c4.tar.gz \
  https://github.com/nicopannu/curso-cloud-formatec-c2-2026/archive/refs/heads/m2-c4.tar.gz

tar xzf m2-c4.tar.gz

cd curso-cloud-formatec-c2-2026-m2-c4/apps/sorny-swarm

docker build -t sorny/payment-service:swarm-v1 ./payment-service
docker build -t sorny/purchase-service:swarm-v1 ./purchase-service

docker image ls | grep sorny
```

> Nota docente: esta duplicacion es intencional. Sirve para explicar por que en un entorno real se usa un registry. Swarm necesita que cada nodo pueda resolver la imagen indicada en el stack. En produccion, el flujo normal seria `build -> push a ECR -> workers hacen pull`.

Checkpoint:

```text
Por que descargamos artefactos versionados en vez de copiar Dockerfiles a mano?
```

Respuesta esperada:

```text
Porque el Dockerfile es parte del codigo fuente.
Versionarlo permite reproducibilidad, revision y trazabilidad.
Copiar/pegar desde una guia es fragil y no representa un flujo real de delivery.
```

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

Decision de publicacion de puertos:

```text
En este lab usamos ports.mode: host.

Motivo:
- el ALB apunta directamente a las EC2 workers;
- cada worker expone realmente 5003 y 5004 en el host;
- evitamos depender del routing mesh de Swarm para el trafico externo;
- con 2 replicas y 2 workers, Docker tiende a ubicar una replica por worker porque el puerto host no puede duplicarse en el mismo nodo.
```

Trade-off:

```text
mode: host es mas explicito para este lab y se parece al modelo ALB -> instancia:puerto.
La alternativa con routing mesh abstrae mas, pero agrega comportamiento de red que puede confundir la clase inicial.
```

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

## Fase 10: Probar desde los workers

Con el manager en `Drain`, no usar el manager como punto principal de prueba HTTP de las APIs. En este lab el ALB apunta solo a los workers y las tasks tienen restriccion `node.role == worker`.

En cada worker:

```bash
curl --max-time 10 -s http://localhost:5004/api/payments/health
curl --max-time 10 -s http://localhost:5003/api/purchases/health
```

Con `mode: host`, cada worker publica el puerto en la EC2. En este lab esperamos que ambos workers respondan en `5003` y `5004` porque hay 2 replicas por servicio y 2 workers.

Observar `hostname` e `ips` en la respuesta. Repetir varias veces:

```bash
for i in $(seq 1 5); do curl --max-time 10 -s http://localhost:5003/api/purchases/health; echo; done
```

Pregunta de checkpoint:

```text
Por que no siempre responde el mismo hostname?
```

Nota docente:

```text
Si el manager esta en Drain, no usarlo para validar trafico HTTP de aplicacion.
El manager administra el cluster; los workers son el plano de datos del lab.
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
El ALB balancea entre EC2 workers.
Cada worker expone los puertos 5003 y 5004 con `mode: host`.
Swarm mantiene el estado deseado de replicas y reubica tareas ante fallas.
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
| Razonamiento | Explica ALB vs Swarm, replicas y publicacion de puertos en workers | Describe pasos pero con poca decision | Solo ejecuta comandos |
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
