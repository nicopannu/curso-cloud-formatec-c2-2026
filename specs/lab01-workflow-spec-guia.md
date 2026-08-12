# Guía de spec — LAB01: workflow de despliegue

## Propósito

En LAB01 vas a construir, con ayuda de un agente, el workflow de GitHub Actions que ejecuta el Terraform de infraestructura. El workflow **no se entrega terminado**: se diseña en clase a partir de este spec.

El objetivo del ejercicio es practicar el recorrido:

```text
necesidad → spec → plan del agente → revisión → workflow → ejecución
```

El foco de la clase sigue siendo monitoreo. El workflow es el mecanismo que deja disponible la infraestructura sobre la que vas a observar logs, métricas y alarmas.

---

## Contexto que el agente debe conocer

El repositorio ya contiene Terraform en `terraform/infra/`. Ese Terraform debe desplegar una infraestructura pequeña de Banco Patacon:

- una EC2 frontend con nginx y una página estática;
- una EC2 backend con una API Flask;
- un IAM instance profile con `CloudWatchAgentServerPolicy`;
- security groups para HTTP;
- CloudWatch Agent enviando logs del frontend y backend.

El workflow no debe crear recursos de monitoreo. En LAB01 esos recursos se configuran manualmente desde la consola. LAB02 los declarará con Terraform.

---

## Resultado esperado del workflow

Crear `.github/workflows/deploy-infra.yml` con un workflow manual (`workflow_dispatch`) que permita seleccionar una acción:

- `apply`: valida, planifica y despliega `terraform/infra`;
- `destroy`: elimina la infraestructura creada por el lab.

El workflow debe mostrar al finalizar los outputs de Terraform, especialmente:

- `frontend_url`;
- `backend_url`;
- `backend_health_url`.

---

## Requerimientos funcionales

### Disparador

- Solo `workflow_dispatch`.
- Input obligatorio `action`.
- Opciones: `apply` y `destroy`.
- No agregar `push` ni `pull_request`: durante esta clase el despliegue se dispara de forma explícita.

### Preparación

- Usar `actions/checkout@v4`.
- Usar `hashicorp/setup-terraform@v3`.
- Trabajar en `terraform/infra` mediante `defaults.run.working-directory` o `-chdir`.
- Configurar la región `us-east-1`.
- Usar la variable de repositorio `TF_STATE_BUCKET` para el bucket S3 de Terraform state; no hardcodear el nombre del bucket en el workflow.
- Usar una key por identidad: `m3-c5/<student_identity>/infra.tfstate`.

### Credenciales

- Usar las credenciales precargadas en GitHub Actions para la cuenta del curso.
- No escribir AK/SAK en el repositorio.
- No imprimir valores de secrets.
- Usar `aws-actions/configure-aws-credentials@v4` con los secrets definidos por el curso.
- Incluir `permissions: contents: read`.
- No usar OIDC en esta primera versión salvo que el profesor cambie explícitamente el diseño.

### Terraform

Para `apply`:

1. `terraform fmt -check`;
2. `terraform init`;
3. `terraform validate`;
4. `terraform plan`;
5. `terraform apply`;
6. `terraform output`.

Para `destroy`:

1. `terraform init`;
2. `terraform validate`;
3. `terraform destroy`.

Usar `-input=false` y aprobación no interactiva dentro del workflow. El workflow debe fallar si falla cualquier paso de Terraform.

### Identidad de recursos

El workflow debe recibir o definir un `student_identity`/`deployment_id` para evitar colisiones entre ejecuciones. El valor debe ser visible en el nombre de los recursos y consistente entre `apply` y `destroy`.

### Seguridad operativa

- Agregar `timeout-minutes` al job.
- No crear SNS, dashboards, alarmas ni metric filters desde el workflow.
- No incluir cleanup destructivo fuera de la acción `destroy` elegida manualmente.
- El README y la guía deben explicar que `destroy` es obligatorio al terminar.

---

## Criterios para revisar el plan del agente

Antes de aceptar el plan, verificá:

- ¿El agente entendió que el workflow es manual?
- ¿Separó `apply` y `destroy`?
- ¿Usa el directorio correcto?
- ¿Valida antes de aplicar?
- ¿Muestra outputs sin exponer credenciales?
- ¿No agregó monitoreo como código antes de LAB02?
- ¿El destroy usa el mismo identificador que apply?

Si algo no coincide, corregí el spec o pedile al agente que ajuste el plan. No aceptes código solo porque compila.

---

## Prompt inicial para Cursor Plan Mode

```text
Leé el repositorio y este spec completo.

Quiero que armes un plan, no que edites archivos todavía, para crear
.github/workflows/deploy-infra.yml.

El workflow debe cumplir exactamente este spec. Revisá primero
terraform/infra y explicá qué comandos, secrets, inputs y outputs
necesita. No agregues dashboards, alarmas, metric filters ni otros
recursos de monitoreo: eso se hará por consola en LAB01 y con
Terraform en LAB02.

Mostrá:
1. archivos que vas a crear o modificar;
2. pasos del workflow;
3. riesgos o ambigüedades;
4. cómo verificaríamos el resultado.
Esperá mi aprobación antes de implementar.
```

Después de revisar el plan, se puede pedir al agente que implemente únicamente lo aprobado.

---

## Fuera de alcance

- Construir el workflow sin revisar el plan.
- Crear monitoreo mediante Terraform en LAB01.
- Usar Grafana, Prometheus, X-Ray o SNS.
- Desplegar frontend y backend con contenedores.
- Resolver todavía el LAB02 completo.

---

## Verificación mínima del workflow

Antes de ejecutar recursos reales:

```bash
# Revisar cambios
 git diff -- .github/workflows/deploy-infra.yml

# Validar Terraform localmente (sin configurar el backend remoto)
 terraform -chdir=terraform/infra init -backend=false
 terraform -chdir=terraform/infra validate
```

Luego el profesor ejecuta `apply`, comprueba URLs y logs, y finalmente ejecuta `destroy` al cerrar la clase.
