# Demo docente — TP final, Ejercicio 3

- **Tema:** resiliencia, monitoreo proactivo y despliegues inmutables con Docker, GitHub Actions y Kubernetes
- **Escenario:** fintech PagoDigital
- **Duración sugerida:** 25–35 minutos
- **Directorio:** `labs/tp-final/`

## Contexto de la demo

El microservicio **Pagos API** llama sincrónicamente a **Notificaciones por Correo**. Si esa dependencia queda lenta y el cliente no aplica timeout, las solicitudes de pagos retienen threads. Cuando se ocupan casi todos los threads, también se degradan las respuestas del servicio; si continúan entrando solicitudes, puede producirse una caída en cascada.

La demo permite observar la saturación antes del colapso, recuperarse con límites de espera y desplegar una nueva imagen sin editar contenedores activos. Los endpoints procesan operaciones sintéticas: no se integra con medios de pago, correo real ni datos de usuarios.

## Objetivos de la demo

- Relacionar latencia de una dependencia con solicitudes en curso y saturación del servicio principal.
- Configurar una alerta temprana sobre una métrica operacional observable.
- Comparar una espera sin límite con una llamada acotada por timeout.
- Construir imágenes Docker asociadas al SHA del commit, sin `latest`.
- Observar `RollingUpdate`, readiness probes y reemplazo gradual de Pods.
- Distinguir CI de un despliegue autorizado a EKS.

## Arquitectura

```text
Generador de tráfico
        |
        v
Service pagos-api → Deployment pagos-api (2 Pods; 1 worker × 5 threads)
        |                                      |
        |                                      +-- /metrics
        v
Service notificaciones → Deployment notificaciones (2 Pods)
                                               |
Prometheus descubre Pods de pagos y evalúa alerta por solicitudes en curso
                                               |
GitHub Actions CI → ECR (tags inmutables con SHA) → EKS (RollingUpdate)
```

**Métrica de saturación:** `payment_requests_in_flight`, solicitudes que están esperando a Notificaciones. Cada Pod de pagos sirve hasta cinco threads de aplicación. Prometheus genera `PagoApiCercaDeSaturacion` si algún Pod mantiene **4 o más solicitudes en curso durante 15 segundos**. Es un umbral temprano de advertencia: 4/5 threads ocupados deja poco margen, sin esperar a que el proceso quede totalmente bloqueado.

La regla sólo muestra el estado en la interfaz de Prometheus. No hay Alertmanager ni canal de notificación; para que la señal sea accionable hay que agregar routing, responsable y runbook. En producción también correlacionaríamos latencia, errores, saturación del pool, resultados funcionales y experiencia del usuario.

## Artefactos

- `app/pagos/`: API sintética, contador de concurrencia y Dockerfile.
- `app/notificaciones/`: dependencia con demora controlable y Dockerfile.
- `tests/`: pruebas unitarias de respuesta, timeout y métrica.
- `k8s/`: namespace, workloads parametrizados, probes, límites y Prometheus.
- `.github/workflows/tp-final-ej3-ci.yml`: CI sin credenciales AWS.
- `.github/workflows/tp-final-ej3-deploy.yml`: publicación en ECR y actualización manual a EKS con OIDC.
- `scripts/generate-load.py`: carga concurrente acotada para observar el síntoma.
- `scripts/e2e-local.py`: prueba HTTP local entre los dos servicios, incluyendo métrica de saturación, timeout y recuperación.
- `scripts/deploy-manifests.sh`: despliegue de los manifests renderizados desde una terminal ya autenticada.

## Preparación local

Requisitos: Python 3.12, Docker, `kubectl`, `envsubst` (`gettext-base`) y un cluster Kubernetes de laboratorio. La validación autorizada en AWS usa un cluster EKS temporal en `us-east-1`; la ventana máxima aprobada para ese cluster es de cuatro horas y se destruye al terminar la prueba.

Desde la raíz del repositorio:

```bash
cd labs/tp-final
python3 -m venv .venv
. .venv/bin/activate
python3 -m pip install -r app/pagos/requirements.txt
python3 -m unittest discover -s tests -v
python3 scripts/e2e-local.py
```

Construcción local con identificador inmutable —no usar `latest`—:

```bash
IMAGE_TAG="$(git rev-parse HEAD)"
docker build --build-arg APP_VERSION="$IMAGE_TAG" \
  --tag "pagodigital-pagos:$IMAGE_TAG" app/pagos
docker build --build-arg APP_VERSION="$IMAGE_TAG" \
  --tag "pagodigital-notificaciones:$IMAGE_TAG" app/notificaciones
```

El tag SHA identifica el commit; para una cadena de suministro estricta, fijar también las imágenes base por digest y guardar/firmar el digest resultante. El Dockerfile usa una versión menor de Python y los workflows no reemplazan escaneo de dependencias ni aprobación de releases.

## Demo en Kubernetes

### 1. Verificar el cluster y preparar imágenes

Elegí un cluster descartable ya existente. No apuntes a workloads de otros labs ni a producción. Comprobá el contexto antes de aplicar:

```bash
kubectl config current-context
kubectl get nodes
```

Para una ejecución local, cargá las imágenes al cluster local según su herramienta. Para EKS, publicá las imágenes en ECR con tags SHA antes de renderizar `k8s/workloads.yaml.tpl`. La sección **Despliegue opcional en la cuenta AWS del curso** detalla los prerequisitos.

Renderizá los manifests. Reemplazá las imágenes por imágenes accesibles al cluster:

```bash
export PAYMENTS_IMAGE="pagodigital-pagos:$IMAGE_TAG"
export NOTIFICATIONS_IMAGE="pagodigital-notificaciones:$IMAGE_TAG"
export APP_VERSION="$IMAGE_TAG"
export NOTIFICATION_TIMEOUT_SECONDS="1.5"

envsubst '${PAYMENTS_IMAGE} ${NOTIFICATIONS_IMAGE} ${APP_VERSION} ${NOTIFICATION_TIMEOUT_SECONDS}' \
  < k8s/workloads.yaml.tpl > /tmp/tp-final-ej3-workloads.yaml
kubectl apply -f k8s/namespace.yaml
kubectl apply -f /tmp/tp-final-ej3-workloads.yaml
kubectl apply -f k8s/prometheus.yaml
kubectl rollout status deployment/pagos-api -n tp-final-ej3 --timeout=5m
kubectl rollout status deployment/notificaciones -n tp-final-ej3 --timeout=5m
kubectl rollout status deployment/prometheus -n tp-final-ej3 --timeout=5m
kubectl get pods,services -n tp-final-ej3
```

### 2. Observar una degradación antes del colapso

En la terminal del cluster, configurá el fallo sintético: Notificaciones demora 45 segundos y Pagos no tiene timeout. Estos valores reproducen el patrón defectuoso del caso; **no son valores recomendados**.

```bash
kubectl set env deployment/notificaciones -n tp-final-ej3 \
  NOTIFICATION_DELAY_SECONDS=45
kubectl rollout status deployment/notificaciones -n tp-final-ej3 --timeout=5m
kubectl set env deployment/pagos-api -n tp-final-ej3 \
  NOTIFICATION_TIMEOUT_SECONDS=0
kubectl rollout status deployment/pagos-api -n tp-final-ej3 --timeout=5m
```

Abrí dos terminales adicionales:

```bash
kubectl port-forward -n tp-final-ej3 service/pagos-api 18080:80
```

```bash
kubectl port-forward -n tp-final-ej3 service/prometheus 9090:9090
```

Generá tráfico desde la raíz del repositorio:

```bash
python3 labs/tp-final/scripts/generate-load.py \
  --concurrency 12 --duration 75
```

En <http://localhost:9090/alerts>, observá `PagoApiCercaDeSaturacion`. En la vista **Graph**, consultá:

```promql
max by (pod) (payment_requests_in_flight{namespace="tp-final-ej3"})
```

**Checkpoint:** antes de que todos los threads queden retenidos, identificar qué Pod alcanzó 4 solicitudes en curso, cuánto tiempo lleva la condición y qué dependencia explica la espera. El alert expresa saturación del proceso; no prueba por sí solo que todos los pagos hayan fallado.

### 3. Aplicar una mitigación segura

Restaurá una espera acotada. La API de demo registra que la notificación se difirió, pero mantiene la respuesta sintética del pago; en un sistema real eso requiere idempotencia y un patrón durable como transactional outbox/cola para no perder notificaciones.

```bash
kubectl set env deployment/pagos-api -n tp-final-ej3 \
  NOTIFICATION_TIMEOUT_SECONDS=1.5
kubectl rollout status deployment/pagos-api -n tp-final-ej3 --timeout=5m
```

Volvé a ejecutar el generador. La duración de espera debería limitarse, `payment_notification_results_total{result="timeout"}` debería crecer mientras la dependencia esté lenta y `payment_requests_in_flight` debería volver a bajar. Luego recuperá la dependencia:

```bash
kubectl set env deployment/notificaciones -n tp-final-ej3 \
  NOTIFICATION_DELAY_SECONDS=0
kubectl rollout status deployment/notificaciones -n tp-final-ej3 --timeout=5m
```

Timeout no equivale a rollback de una operación de pago y los retries automáticos pueden duplicar operaciones no idempotentes. La demo evita retries; la notificación podría procesarse asincrónicamente.

### 4. Demostrar actualización inmutable

La CI corre con `push`/`pull_request`, sin credenciales AWS: prueba la API y construye imágenes etiquetadas con el SHA completo. Para esta validación, el workflow de CD también se dispara sólo con `push` a `demo/tp-final-ej3-resiliencia` y queda protegido por el Environment `tp-final-ej3`; el workflow conserva `workflow_dispatch` para su uso manual una vez disponible en la branch default. El Environment debe permitir únicamente la branch aprobada para este test. La ejecución usa OIDC, no access keys guardadas en GitHub.

La estrategia del Deployment ya configura:

```yaml
strategy:
  type: RollingUpdate
  rollingUpdate:
    maxUnavailable: 0
    maxSurge: 1
```

Cada nueva imagen lleva un tag distinto —`pagos-<SHA>` y `notificaciones-<SHA>`— y no se sobrescribe. `kubectl apply` actualiza la referencia a la imagen; Kubernetes crea Pods nuevos, espera sus readiness probes y termina los anteriores gradualmente. El workflow espera `kubectl rollout status` y valida `/readyz`, `/version` y un POST sintético.

Tres pasos conceptuales mínimos de GitHub Actions:

1. `actions/checkout` descarga el commit.
2. Pruebas y `docker build` construyen imágenes etiquetadas por SHA.
3. En una ejecución manual autorizada, login temporal a ECR/EKS, push inmutable y actualización del Deployment con comprobación de rollout.

**Checkpoint:** explicar por qué modificar el filesystem de un contenedor no produce una versión reproducible, por qué `latest` no identifica el artefacto y qué condición de readiness debe cumplirse antes de retirar Pods anteriores.

## Despliegue opcional en la cuenta AWS del curso

La validación autorizada crea un cluster EKS temporal y un managed node group pequeño en la VPC default existente, más un repositorio ECR inmutable, un rol IAM para GitHub Actions y los recursos Kubernetes de la demo. La duración máxima autorizada del cluster es de cuatro horas; al terminar se eliminan el cluster, node group, ECR y rol IAM creados para esta prueba. Se conservan la VPC default y el proveedor OIDC preexistente. No se crea NAT Gateway, Load Balancer de aplicación ni endpoint público para los servicios.

### Requisitos previos

- Cuenta y región verificadas: perfil `curso`, `us-east-1`.
- Cluster EKS temporal, nodos disponibles y permiso ECR de pull para el rol de los nodos.
- Namespace `tp-final-ej3` creado una vez por el administrador.
- Repositorio ECR privado con **tag mutability `IMMUTABLE`**.
- Environment de GitHub `tp-final-ej3` con variables `AWS_REGION`, `AWS_ROLE_ARN`, `EKS_CLUSTER_NAME`, `ECR_REPOSITORY` y `KUBECTL_VERSION`, protegido con reviewers requeridos y allowlist de branch `demo/tp-final-ej3-resiliencia`; el `sub` OIDC limitado a un Environment no reemplaza esa protección.
- Proveedor OIDC de GitHub y rol con trust limitado a `repo:nicopannu/curso-cloud-formatec-c2-2026:environment:tp-final-ej3` y audiencia `sts.amazonaws.com`.
- El rol debe poder subir imágenes sólo al repositorio ECR elegido, describir el cluster, actualizar/restaurar su allowlist (`eks:UpdateClusterConfig`, `eks:DescribeUpdate`) y autenticarse en Kubernetes con permisos limitados al namespace de la demo.
- El endpoint público EKS debe iniciar con una allowlist restringida. El workflow agrega temporalmente sólo el IPv4 `/32` del runner, conserva los CIDRs originales y los restaura al final incluso si falla un paso posterior. Si la ejecución se interrumpe abruptamente, queda el CIDR original más el `/32` del runner; nunca se abre a `0.0.0.0/0`.

Comprobación de identidad antes de cualquier acción AWS:

```bash
aws --profile curso --region us-east-1 sts get-caller-identity
aws --profile curso --region us-east-1 eks list-clusters
```

Para crear el repositorio ECR sólo si no existe (acción AWS con costo de almacenamiento si se publican imágenes):

```bash
aws --profile curso --region us-east-1 ecr describe-repositories \
  --repository-names formatec/tp-final-ej3

aws --profile curso --region us-east-1 ecr create-repository \
  --repository-name formatec/tp-final-ej3 \
  --image-tag-mutability IMMUTABLE \
  --image-scanning-configuration scanOnPush=true
```

El segundo comando es sólo para el caso en que la primera consulta confirme que no existe y Nicolas autorice esa creación. La guía no almacena claves AWS ni requiere secrets de access key.

### Costos, alcance y cleanup

- El cluster EKS y su node group generan costo mientras existan; esta validación tiene un límite operativo de cuatro horas y cleanup inmediato al finalizar. No se da una estimación monetaria aquí porque el lookup de pricing no estuvo disponible en esta sesión.
- El node group temporal ejecuta cuatro Pods de aplicación y un Pod Prometheus. No se crea NAT Gateway ni Load Balancer.
- ECR almacena las imágenes publicadas y puede generar costo de almacenamiento; definir una política de lifecycle o borrar tags/repositorio al finalizar si ya no se necesitan.
- No se crean Load Balancers ni direcciones públicas para las aplicaciones. Prometheus se consulta con `kubectl port-forward`.
- Al finalizar, verificar primero el contexto y luego eliminar sólo el namespace de la demo:

```bash
kubectl config current-context
kubectl delete namespace tp-final-ej3
```

- Para esta validación temporal, borrar el namespace después de capturar evidencia y eliminar el cluster/node group, repositorio ECR y rol IAM creados exclusivamente para el demo. Verificar cada recurso por nombre/tag antes del borrado.
- No borrar la VPC default, el proveedor OIDC compartido, roles de otros labs ni recursos de otros módulos.

## Entregables / evidencia de la demo

- URL del run exitoso de CI y SHA de las imágenes.
- Captura o consulta de Prometheus antes y después de la mitigación.
- Salida de `kubectl rollout status` y `kubectl get pods` con réplicas Ready.
- Respuesta de `/version` y smoke test HTTP posterior al rollout.
- Explicación breve de la métrica, umbral, causa observada, timeout, inmutabilidad y estrategia de actualización.

## Criterios de evaluación sugeridos — 40 puntos

| Criterio | Puntos |
|---|---:|
| Selecciona una métrica de saturación y justifica umbral/ventana | 8 |
| Explica la cadena latencia → solicitudes en curso → agotamiento de threads | 8 |
| Propone timeout, health/readiness checks y una recuperación coherente | 6 |
| Usa tags Docker por SHA, evita `latest` y explica inmutabilidad | 6 |
| Separa CI sin credenciales de CD manual con permisos mínimos | 6 |
| Explica `RollingUpdate`, evidencia de disponibilidad, costos y cleanup | 6 |

## Qué no cubre esta demo

No representa transacciones monetarias reales, no garantiza entrega de correo, no implementa transactional outbox, circuit breaker, autoscaling, tracing distribuido, Alertmanager, firma de imágenes, promoción multiambiente ni rollback automatizado. Esos temas son extensiones; se mantienen fuera del recorrido central para que la clase se concentre en la señal de saturación y el despliegue inmutable.
