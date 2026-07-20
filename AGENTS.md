# AGENTS.md — Formatec Cloud 2026 · M3-C2 Ansible

## Contexto

- Curso: Arquitectura e Ingeniería Cloud | C2 — Formatec 2026.
- Módulo: M3-C2 — Gestión de configuración con Ansible.
- Branch: `m3-c2-lab`.
- Escenario: CloudCuyo necesita configurar de forma homogénea dos servidores web.
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
8. Cada LAB debe incluir narrativa, objetivos, arquitectura, actividades, checkpoints, entregables, evaluación y limpieza.
9. No usar scripts `shell` monolíticos cuando exista un módulo idempotente de Ansible.
10. Validar primera y segunda ejecución, drift, HTTP y destrucción antes de afirmar que el lab funciona end-to-end.

## Validación local

```bash
./scripts/validate-lab.sh
```

## Validación real autorizada

El camino completo incluye: generar claves temporales, `terraform apply`, esperar cloud-init, generar/copiar inventario, ejecutar Ansible local y remoto, comprobar idempotencia, HTTP y drift, y finalmente `terraform destroy` con verificación de limpieza.
