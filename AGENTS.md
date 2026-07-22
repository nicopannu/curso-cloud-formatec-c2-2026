# AGENTS.md — Formatec Cloud 2026 · M3-C2 Ansible

## Contexto

- Curso: Arquitectura e Ingeniería Cloud | C2 — Formatec 2026.
- Módulo: M3-C2 — Gestión de configuración con Ansible.
- Branch: `m3-c2-lab`.
- Escenario: CloudCuyo comienza con dos servidores web y en LAB03 incorpora `web03` para practicar variables por host y cambios dirigidos.
- Terraform crea la infraestructura y realiza un bootstrap mínimo; Ansible administra la configuración posterior.

## Fuente de verdad

Las guías de `guias/` definen el orden, alcance, checkpoints y entregables. Este repositorio incluye infraestructura Terraform ejecutable y un proyecto Ansible de referencia para que el foco de la clase sea gestión de configuración, no reconstruir una VPC desde cero.

## Reglas de mantenimiento

1. Antes de editar, listar archivos y objetivo.
2. No ejecutar `terraform apply` o `destroy` sin autorización explícita.
3. No commitear state, tfvars reales, inventarios generados, credenciales ni claves privadas.
4. Mantener estado Terraform local; este laboratorio no usa backend remoto.
5. Terraform sólo puede leer claves públicas. Ninguna clave privada debe entrar al state o User Data.
6. El acceso SSH de los managed nodes debe aceptar origen únicamente desde el Security Group del control node.
7. Mantener las guías en español y dirigidas al alumno.
8. Cada LAB debe incluir narrativa, objetivos, arquitectura, actividades, checkpoints, entregables y limpieza. Las guías de M3-C2 no incluyen criterios de evaluación salvo pedido explícito.
9. No usar scripts `shell` monolíticos cuando exista un módulo idempotente de Ansible.
10. Validar primera y segunda ejecución, drift, `--limit`, personalización por host, HTTP y destrucción antes de afirmar que el lab funciona end-to-end.
11. Mantener el direccionamiento privado determinista: controller `10.30.10.5`, web01 `10.30.10.10`, web02 `10.30.10.11` y web03 `10.30.10.12`.

## Validación local

```bash
./scripts/validate-lab.sh
```

## Validación real autorizada

El camino completo incluye: generar claves temporales, `terraform apply`, esperar cloud-init, verificar el inventario fijo, copiar la clave managed, ejecutar Ansible local y remoto, comprobar idempotencia, HTTP y drift, y finalmente `terraform destroy` con verificación de limpieza.
