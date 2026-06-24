# Guia Contenedores LAB01: Sorny — Docker local o EC2 bootstrap

**Objetivo:** Instalar o usar Docker, probar contenedores, construir una imagen propia y entender que Docker sin orquestador puede correr varios contenedores, pero no administra un servicio escalable por si solo.

**Duracion estimada:** 90-120 minutos

**Modulo:** Modulo 2 — Clase 4: Contenedores y Serverless

---

## Contexto narrativo

Sorny tiene responsabilidades separadas: frontend, purchase, delivery y payment. El problema de esta clase es que esos componentes todavia necesitan un modelo de ejecucion claro: algunos convienen como contenedores, otros pueden pasar a serverless.

El siguiente paso es empaquetar servicios. Antes de hablar de Docker Swarm o Lambda, necesitamos entender Docker como unidad minima:

```text
Dockerfile -> imagen -> contenedor -> puerto/logs/limpieza
```

En esta guia no migramos Sorny todavia. Preparamos la base tecnica para hacerlo en la guia siguiente.

---

## Caminos del lab

### Opcion A — Docker local con Windows + WSL2, recomendada si se puede

Usar esta opcion si tu PC permite virtualizacion y podes instalar Docker Desktop.

Modelo:

```text
Windows
  |
  +-- Docker Desktop
        |
        +-- WSL2 backend
              |
              +-- contenedores Linux
```

Tambien sirve si usas macOS o Linux con Docker Engine/Docker Desktop.

### Opcion B — EC2 bootstrap con CloudFormation

Usar esta opcion si:

- tu PC no tiene recursos suficientes;
- no podes activar virtualizacion;
- no podes instalar WSL2 o Docker Desktop;
- estas en una maquina con restricciones administrativas.

Modelo:

```text
Alumno -> navegador/curl -> EC2 publica:8080 -> contenedor Docker:8080
```

Template:

```text
cloudformation/contenedores-lab01-docker-ec2-bootstrap.yaml
```

El template levanta una EC2 Amazon Linux 2023 con Docker instalado y puerto 8080 permitido por Security Group.

---

## Objetivos de aprendizaje

Al finalizar, deberias poder:

- explicar imagen vs contenedor;
- ejecutar y listar contenedores;
- construir una imagen propia con Dockerfile;
- publicar un puerto del contenedor hacia el host;
- ver hostname e IP internas de un contenedor;
- correr varias replicas manuales de una misma imagen;
- explicar por que Docker sin Swarm/Kubernetes no es un orquestador de servicios;
- conectar este aprendizaje con Docker Swarm: escalar un servicio requiere algo mas que `docker run`.

---

## Pre-requisitos

### Para Opcion A — Windows 10 + WSL2 + Docker Desktop

Esta guia toma Windows 10 como objetivo base porque suele ser el caso con mas pasos previos. En Windows 11 el flujo es similar, pero algunas pantallas pueden cambiar.

Requisitos minimos:

1. Windows 10 64 bits, version 2004 o superior, build 19041 o superior.
2. Virtualizacion habilitada en BIOS/UEFI.
3. Permisos de administrador para instalar componentes.
4. Conexion a internet para descargar WSL, Ubuntu, Docker Desktop y el paquete del lab desde la branch `m2-c4`.

#### Paso A.1: Verificar version de Windows

Abrir PowerShell como usuario normal y ejecutar:

```powershell
winver
```

Validar:

```text
Windows 10 version 2004 o superior
Build 19041 o superior
```

Si la version es anterior, Docker Desktop con WSL2 puede fallar o pedir actualizaciones.

#### Paso A.2: Verificar virtualizacion

Abrir:

```text
Task Manager > Performance > CPU
```

Buscar:

```text
Virtualization: Enabled
```

Si aparece `Disabled`, hay que habilitar virtualizacion en BIOS/UEFI. El nombre cambia segun fabricante:

- Intel VT-x;
- Intel Virtualization Technology;
- AMD-V;
- SVM Mode.

#### Paso A.3: Instalar WSL2

Abrir PowerShell como Administrador y ejecutar:

```powershell
wsl --install
```

Si el comando anterior no esta disponible, usar instalacion manual:

```powershell
dism.exe /online /enable-feature /featurename:Microsoft-Windows-Subsystem-Linux /all /norestart
dism.exe /online /enable-feature /featurename:VirtualMachinePlatform /all /norestart
```

Reiniciar Windows.

Luego definir WSL2 como version default:

```powershell
wsl --set-default-version 2
```

Instalar Ubuntu desde Microsoft Store o con:

```powershell
wsl --install -d Ubuntu
```

Abrir Ubuntu una vez y crear usuario Linux.

Validar:

```powershell
wsl -l -v
```

Resultado esperado:

```text
  NAME      STATE           VERSION
* Ubuntu    Running         2
```

Si Ubuntu aparece en version 1:

```powershell
wsl --set-version Ubuntu 2
```

#### Paso A.4: Instalar Docker Desktop

1. Descargar Docker Desktop desde:

```text
https://www.docker.com/products/docker-desktop/
```

2. Ejecutar instalador como Administrador.
3. Dejar habilitada la opcion:

```text
Use WSL 2 instead of Hyper-V
```

4. Reiniciar si el instalador lo solicita.
5. Abrir Docker Desktop.

#### Paso A.5: Configurar Docker Desktop con WSL2

En Docker Desktop:

```text
Settings > General
```

Validar:

```text
Use the WSL 2 based engine = enabled
```

Luego:

```text
Settings > Resources > WSL Integration
```

Habilitar integracion para la distro Ubuntu.

Aplicar cambios:

```text
Apply & Restart
```

#### Paso A.6: Validar desde PowerShell y desde Ubuntu/WSL

En PowerShell:

```powershell
docker version
docker run hello-world
```

En Ubuntu/WSL:

```bash
docker version
docker run hello-world
```

Resultado esperado:

```text
Hello from Docker!
```

Si `docker version` muestra cliente pero no servidor, Docker Desktop no esta iniciado o el backend WSL2 no termino de levantar.

#### Troubleshooting rapido Windows 10

| Sintoma | Causa probable | Accion |
|---|---|---|
| `wsl` no existe | Windows viejo o WSL no instalado | Actualizar Windows o usar instalacion manual con `dism` |
| Ubuntu aparece VERSION 1 | Distro en WSL1 | `wsl --set-version Ubuntu 2` |
| Docker Desktop no arranca | Virtualizacion deshabilitada | Habilitar VT-x/AMD-V en BIOS |
| `Cannot connect to Docker daemon` | Docker Desktop apagado | Abrir Docker Desktop y esperar estado Running |
| Docker no aparece en Ubuntu | WSL Integration deshabilitada | Activar integracion en Docker Desktop |
| Error de permisos en Windows corporativo | Sin permisos admin | Usar Opcion B con EC2 bootstrap |

### Para Opcion B — EC2

1. AWS Console en `us-east-1`.
2. VPC y subnet publica existentes.
3. Instance Profile SSM existente, por ejemplo `cloudcuyo-ssm-role`.
4. Permisos para CloudFormation y EC2.
5. Subnet publica con salida a internet para descargar Docker, imagenes base y el paquete del lab desde la branch `m2-c4`.

Crear stack:

```text
CloudFormation > Create stack > Upload template
Template: cloudformation/contenedores-lab01-docker-ec2-bootstrap.yaml
Stack name: sorny-docker-bootstrap
```

Parametros principales:

| Parametro | Valor sugerido |
|---|---|
| `VpcId` | VPC del laboratorio |
| `SubnetId` | Subnet publica con salida a internet |
| `AllowedHttpCidr` | Tu IP/rango del aula. Para demo puede ser `0.0.0.0/0`, pero no es ideal |
| `InstanceType` | `t3.micro` |
| `SsmInstanceProfileName` | `cloudcuyo-ssm-role` o el profile del curso |

Cuando el stack termine, anotar outputs:

- `PublicDnsName`
- `PublicIp`
- `InstanceId`

Conectarse por Session Manager.

Importante: `CREATE_COMPLETE` indica que CloudFormation creo la EC2, pero el `UserData` puede seguir instalando paquetes durante algunos minutos. Antes de continuar, esperar hasta que Docker exista y el servicio este activo:

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

systemctl is-active docker

docker --version
```

Resultado esperado:

```text
active
Docker version ...
```

Si despues de varios minutos Docker no aparece, revisar:

```bash
tail -n 80 /var/log/user-data.log
```

---

## Fase 1: Probar Docker

Ejecutar:

```bash
docker version
docker run hello-world
docker ps
docker ps -a
docker image ls
```

Preguntas:

- Por que `hello-world` no queda corriendo?
- Que diferencia hay entre una imagen descargada y un contenedor ejecutado?
- Que parte se versionaria en un pipeline real?

---

## Fase 2: Descargar artefactos y construir la imagen Sorny HostInfo

El `Dockerfile` no se copia a mano desde la guia. Forma parte del codigo fuente del curso y se descarga como artefacto versionado desde la branch `m2-c4`.

Descargar el paquete del lab:

```bash
LAB_DIR="$HOME/m2-c4-lab"
mkdir -p "$LAB_DIR"
cd "$LAB_DIR"
rm -rf curso-cloud-formatec-c2-2026-m2-c4 m2-c4.tar.gz

curl -L -o m2-c4.tar.gz \
  https://github.com/nicopannu/curso-cloud-formatec-c2-2026/archive/refs/heads/m2-c4.tar.gz

tar xzf m2-c4.tar.gz

cd curso-cloud-formatec-c2-2026-m2-c4/apps/docker-hostinfo
ls -la
```

El directorio debe contener:

```text
app.py
requirements.txt
Dockerfile
```

La app responde con:

- mensaje de saludo;
- nombre del servicio;
- hostname del contenedor;
- IPs vistas desde el contenedor;
- version.

Decision tecnica:

```text
No copiamos Dockerfiles a mano.
El Dockerfile vive junto al codigo y se versiona.
La VM o el pipeline descargan artefactos reproducibles y construyen la imagen.
```

Construir:

```bash
docker build -t sorny-hostinfo:v1 .
```

Ejecutar:

```bash
docker run -d --name sorny-hostinfo-1 -p 8080:8080 sorny-hostinfo:v1
```

Probar local:

```bash
curl http://localhost:8080
```

Si usas EC2, probar desde navegador:

```text
http://<PublicDnsName>:8080
```

Respuesta esperada similar:

```json
{
  "message": "Hola desde Sorny Docker",
  "service": "sorny-hostinfo",
  "hostname": "b4a9d7f0d123",
  "ips": ["172.17.0.2"],
  "version": "v1"
}
```

---

## Fase 3: Inspeccionar contenedor, logs y red

```bash
docker ps
docker logs sorny-hostinfo-1
docker inspect sorny-hostinfo-1
```

Preguntas:

- El hostname coincide con el ID corto del contenedor?
- La IP del contenedor es igual a la IP del host?
- Que significa `-p 8080:8080`?

Modelo:

```text
host:8080 -> contenedor:8080
```

En Windows/local, el host es tu PC. En EC2, el host es la instancia.

---

## Fase 4: Correr varios contenedores de la misma imagen

Docker sin Swarm permite correr varios contenedores de una misma imagen. Lo que no permite es tratarlos como un servicio administrado con balanceo, health checks, scheduling y autoscaling automatico.

Primero correr una segunda replica manual en otro puerto:

```bash
docker run -d --name sorny-hostinfo-2 -p 8081:8080 sorny-hostinfo:v1
```

Probar:

```bash
curl http://localhost:8080
curl http://localhost:8081
```

En EC2:

```text
http://<PublicDnsName>:8080
http://<PublicDnsName>:8081
```

> Si usas EC2 y queres probar `8081` desde navegador, el Security Group tambien debe permitir 8081. Para mantener el lab simple, alcanza con probar `8081` desde dentro de la EC2 con curl.

Comparar respuestas:

- Cada contenedor tiene hostname distinto.
- Cada contenedor tiene IP distinta dentro de la red Docker.
- Ambos salen de la misma imagen `sorny-hostinfo:v1`.

### Discusion: Docker sin Swarm

Docker Engine solo permite hacer esto manualmente:

```text
docker run contenedor 1
docker run contenedor 2
docker run contenedor 3
```

Pero no ofrece por si solo:

- desired count declarativo;
- reemplazo automatico si un contenedor muere;
- balanceador integrado entre replicas;
- despliegue rolling administrado;
- service discovery estable;
- autoscaling por CPU/requests.

Para eso aparecen orquestadores:

- Docker Swarm;
- Kubernetes.

La diferencia entre “EC2 con Docker manual” y “Docker Swarm” en nuestro lab va a estar justamente ahi: **queremos declarar servicios, replicas y recuperacion, no solo ejecutar contenedores manuales**.

---

## Fase 5: Cambiar version y reconstruir

Editar `apps/docker-hostinfo/Dockerfile` o ejecutar pasando variable de entorno:

```bash
docker rm -f sorny-hostinfo-1 sorny-hostinfo-2 || true

docker run -d --name sorny-hostinfo-1 \
  -e APP_VERSION=v2 \
  -p 8080:8080 \
  sorny-hostinfo:v1
```

Probar:

```bash
curl http://localhost:8080
```

Pregunta:

- Esta version cambio la imagen o solo la configuracion del contenedor?
- Que cosas deberian ir en la imagen y que cosas deberian ir como variables de entorno?

---

## Fase 6: Relacion con Sorny

Hoy usamos una app simple. En la siguiente guia, la misma logica se aplica a `purchase-service` y `payment-service`:

```text
servicio en EC2
  Python + pip + systemd
```

pasa a:

```text
servicio como imagen
  Dockerfile + dependencias + comando de arranque
```

Y luego Docker Swarm ejecuta esas imagenes como servicios replicados en dos EC2.

Preguntas de cierre:

- Que gana Sorny si purchase/payment se empaquetan como imagenes?
- Que problema sigue sin resolver si solo corremos `docker run` en una EC2?
- Que necesita aparecer para escalar replicas de forma segura?

---

## Limpieza

```bash
docker rm -f sorny-hostinfo-1 sorny-hostinfo-2 || true
docker image rm sorny-hostinfo:v1 || true
```

Si usaste EC2 solo para este lab, eliminar el stack:

```text
CloudFormation > Stacks > sorny-docker-bootstrap > Delete
```

No eliminar VPC, subnets, roles compartidos ni recursos del curso.

---

## Entregables

1. Camino usado: local o EC2.
2. Evidencia de `docker version`.
3. Dockerfile de `sorny-hostinfo`.
4. Captura o salida de `curl` mostrando `message`, `hostname` e `ips`.
5. Evidencia de dos contenedores corriendo desde la misma imagen.
6. Respuesta breve:
   - Puede Docker sin Swarm correr varios contenedores del mismo servicio?
   - Que le falta para ser una plataforma escalable?
   - Por que Docker Swarm mejora este punto frente a `docker run` manual?

---

## Criterios de evaluacion

- Docker funciona en el camino elegido.
- La imagen `sorny-hostinfo:v1` se construye correctamente.
- El contenedor responde por HTTP.
- La respuesta muestra hostname e IP del contenedor.
- El alumno corre dos contenedores de la misma imagen y entiende el conflicto de puertos.
- La entrega diferencia ejecutar contenedores de operar un servicio escalable.
