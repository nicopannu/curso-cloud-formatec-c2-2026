# Formatec Cloud 2026 — M3-C4 CI/CD

Repositorio del curso **Arquitectura e Ingeniería Cloud | C2**.

**Profesor:** Nicolás Pannucio
**Módulo:** M3 — Clase 4: pipelines CI/CD con GitHub Actions
**Branch del material:** `m3-c4-lab`

## El escenario: dos equipos, dos problemas

**Banco Patacon** opera una solución web en AWS. El trabajo está dividido en dos líneas:

### Equipo de infraestructura

Administra:

- la red AWS;
- la instancia EC2;
- los permisos IAM y la conexión por Systems Manager;
- el bucket temporal usado por Ansible;
- la instalación y configuración de Nginx.

Terraform define la infraestructura y Ansible configura el servidor. El repositorio ya contiene un workflow para automatizar este recorrido, pero el pipeline todavía no puede desplegar: el environment `lab`, sus credenciales y las variables del backend no están configurados.

El problema no se resuelve agregando credenciales al código. Primero hay que comprobar que CI funciona sin acceso a AWS, observar dónde se detiene el deploy y habilitar el environment correcto.

### Equipo de aplicación

Mantiene la página web de Banco Patacon y necesita entregarla como una imagen Docker reproducible. Actualmente el equipo construye y prueba la imagen manualmente. No existe un workflow que garantice que cada cambio:

- pueda convertirse en una imagen;
- inicie correctamente como contenedor;
- responda por HTTP;
- quede asociado al commit que produjo la ejecución.

En esta parte no recibís una aplicación ni un pipeline resueltos. Vas a crear desde cero la página, el Dockerfile y el workflow.

## La misión

Banco Patacon necesita recuperar su pipeline de despliegue de infraestructura y comenzar a construir el pipeline de entrega de su aplicación.

El recorrido completo es:

```text
INFRAESTRUCTURA
push o pull request
→ validar Terraform y Ansible sin credenciales
→ ejecutar plan manual
→ observar el fallo por credenciales ausentes
→ configurar environment lab
→ plan
→ apply
→ configurar Nginx por Ansible sobre SSM
→ comprobar HTTP
→ repetir plan y obtener No changes
→ destroy

APLICACIÓN
crear página Banco Patacon
→ crear Dockerfile
→ construir imagen
→ iniciar contenedor
→ comprobar HTTP
→ crear workflow desde cero
→ repetir build y smoke test en GitHub Actions
→ asociar la evidencia al commit SHA
→ introducir un fallo controlado
→ comprobar que el pipeline bloquea una imagen inválida
→ corregir y recuperar el pipeline
```

LAB02 construye la primera etapa del pipeline de entrega de la aplicación: **build, ejecución, prueba y trazabilidad de la imagen**. Publicar la imagen en un registry y desplegarla en un ambiente quedan como evolución posterior; este laboratorio no debe confundir una imagen validada con una imagen ya desplegada.

## Laboratorios incluidos

| Lab | Guía | Objetivo | Punto de partida |
|---|---|---|---|
| LAB01 | `guias/guia-cicd-lab01-infra.md` | Recuperar el pipeline de infraestructura y completar plan/apply/destroy | Terraform, Ansible y workflow preparados; environment `lab` sin configurar |
| LAB02 | `guias/guia-cicd-lab02-imagen-docker.md` | Construir el pipeline de entrega de la imagen Docker | Desde cero: no vienen `app/`, Dockerfile ni workflow de aplicación |

Completá LAB01 antes de comenzar LAB02. LAB02 no usa AWS ni modifica la infraestructura creada en LAB01.

## Mapa de la branch

```text
.
├── .devcontainer/              # Codespaces con Terraform, AWS CLI, Ansible, Docker y jq
├── .github/workflows/
│   └── infra-ci.yml            # Pipeline preparado para LAB01
├── ansible/                    # Configuración Nginx vía SSM, sin SSH
├── guias/
│   ├── guia-cicd-lab01-infra.md
│   └── guia-cicd-lab02-imagen-docker.md
├── infra/                      # Root Terraform simple, sin módulos
└── scripts/                    # Inventario y validación local
```

`app/` y `.github/workflows/image-ci.yml` no vienen resueltos. Se crean paso a paso durante LAB02.

## 1. Preparar el repositorio personal

Los workflows deben ejecutarse desde un repositorio donde tengas permisos para hacer push, configurar Actions, crear environments y administrar secrets.

Nombre recomendado:

```text
curso-cloud-formatec-nombreapellido-c2-2026
```

Reemplazá `nombreapellido` por tu identidad en minúsculas y sin espacios.

### Si todavía no tenés el repositorio

1. Ingresá a GitHub.
2. Abrí `+` → **New repository**.
3. Usá el nombre recomendado.
4. Elegí visibilidad pública o privada.
5. Si es privado, invitá al docente como colaborador mediante `nicolaspannucio@gmail.com`.
6. No inicialices el repositorio con archivos que contengan credenciales.
7. Copiá la URL HTTPS.

Cloná el repositorio:

```bash
git clone URL_DEL_REPOSITORIO_PERSONAL
cd curso-cloud-formatec-nombreapellido-c2-2026
```

### Si ya usaste el repositorio en clases anteriores

Entrá al repositorio existente y comprobá que no haya cambios pendientes:

```bash
cd curso-cloud-formatec-nombreapellido-c2-2026
git status
```

No cambies de branch con archivos sin guardar.

## 2. Incorporar el starter M3-C4

Agregá el repositorio del curso como remote `upstream`:

```bash
git remote add upstream https://github.com/nicopannu/curso-cloud-formatec-c2-2026.git
```

Si `upstream` ya existe, verificá su URL:

```bash
git remote get-url upstream
```

Descargá la branch del curso y creá tu branch de trabajo:

```bash
git fetch upstream m3-c4-lab
git switch -c m3-c4-lab --track upstream/m3-c4-lab
```

Publicala en tu repositorio personal:

```bash
git push -u origin m3-c4-lab
```

Verificá:

```bash
git branch --show-current
git remote -v
git status
```

Resultado esperado:

```text
m3-c4-lab
```

**Por qué se hace así:** `upstream` conserva la referencia al material del curso y `origin` apunta a tu entrega. Los workflows se ejecutan en tu repositorio, donde podés configurar environments y secrets sin modificar el repositorio docente.

## 3. Habilitar el dispatch manual

GitHub sólo muestra **Run workflow** para workflows disponibles en la default branch del repositorio.

En tu repositorio personal:

1. Abrí **Settings**.
2. Entrá en **Branches**.
3. En **Default branch**, seleccioná `m3-c4-lab`.
4. Confirmá el cambio.
5. Abrí **Actions** y verificá que aparezca `Infra CI/CD - Banco Patacon LAB01`.

Al terminar la clase podés restaurar `main` como default branch si tu repositorio la utiliza para otros materiales.

## 4. Elegir el entorno de trabajo

### Opción A — GitHub Codespaces

En tu repositorio personal:

1. Seleccioná `m3-c4-lab`.
2. Presioná **Code**.
3. Abrí **Codespaces**.
4. Elegí **Create codespace on m3-c4-lab**.
5. Esperá la construcción del devcontainer.

El material docente también puede abrirse en modo de consulta desde:

<https://codespaces.new/nicopannu/curso-cloud-formatec-c2-2026?ref=m3-c4-lab>

Para hacer push y ejecutar tus workflows, trabajá en el Codespace de tu repositorio personal.

Verificá herramientas:

```bash
git branch --show-current
git --version
terraform version
aws --version
ansible --version
docker version
jq --version
```

### Opción B — Entorno local

Necesitás:

- Git;
- Terraform `>= 1.6`;
- AWS CLI;
- Python 3;
- Ansible;
- Docker para LAB02.

LAB01 ejecuta el deploy desde GitHub-hosted runners. No guardes credenciales AWS en archivos locales del proyecto.

## 5. Validar el starter

Desde la raíz:

```bash
./scripts/validate-lab.sh
```

El script revisa estructura, contratos, Terraform e inventario sin ejecutar:

```text
terraform plan
terraform apply
terraform destroy
aws ...
```

`init`, `fmt` y `validate` no crean infraestructura. Las operaciones reales ocurren únicamente en el job manual de GitHub Actions.

## 6. Recorrido esperado

### LAB01

```text
push inicial
→ CI sin credenciales
→ plan manual falla por secrets ausentes
→ configurar environment lab
→ plan exitoso
→ apply Terraform
→ Ansible configura Nginx por SSM
→ smoke test HTTP
→ segundo plan: No changes
→ destroy
```

### LAB02

```text
crear index.html
→ crear Dockerfile
→ build local
→ run + curl
→ crear image-ci.yml
→ build en GitHub runner
→ smoke test
→ artifact de metadata asociado al SHA
```

## 7. Seguridad

Nunca publiques:

- Access Keys o Secret Keys;
- session tokens;
- archivos `.env`;
- `.terraform/`;
- `terraform.tfstate` o backups;
- planes `tfplan`;
- inventarios generados;
- credenciales copiadas en YAML, Terraform, documentación o capturas.

Los secrets de GitHub se configuran desde **Settings → Environments**. No se escriben dentro del workflow.

## 8. Guardar el trabajo

Revisá siempre antes de commitear:

```bash
git status
git diff
```

Después de cada checkpoint:

```bash
git add RUTAS_DEL_LAB
git commit -m "Completar checkpoint M3 C4"
git push
```

El link de entrega debe apuntar a:

```text
https://github.com/<usuario>/curso-cloud-formatec-nombreapellido-c2-2026/tree/m3-c4-lab
```

No hagas merge a `main` hasta completar el cleanup de LAB01 y conservar las evidencias solicitadas.

## Guías

- [LAB01 — Pipeline de infraestructura](guias/guia-cicd-lab01-infra.md)
- [LAB02 — Pipeline de imagen Docker desde cero](guias/guia-cicd-lab02-imagen-docker.md)
