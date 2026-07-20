#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TF_DIR="$ROOT_DIR/terraform/ansible-aws-lab"

fail() { echo "ERROR: $*" >&2; exit 1; }
pass() { echo "OK: $*"; }

command -v terraform >/dev/null || fail "terraform no está instalado"

terraform -chdir="$TF_DIR" fmt -check -recursive
pass "terraform fmt"

terraform -chdir="$TF_DIR" init -backend=false -input=false >/dev/null
terraform -chdir="$TF_DIR" validate
pass "terraform validate"

bash -n "$ROOT_DIR/scripts/render-inventory.sh"
bash -n "$ROOT_DIR/scripts/validate-lab.sh"
bash -n "$TF_DIR/user-data/ansible-control.sh.tftpl"
pass "sintaxis Bash"

python3 - "$ROOT_DIR" <<'PY'
from pathlib import Path
import sys
root=Path(sys.argv[1])
required=[
 'README.md','AGENTS.md',
 'guias/guia-ansible-lab01-control-node-terraform.md',
 'guias/guia-ansible-lab02-gestion-servidores.md',
 'ansible/playbooks/control-node.yml','ansible/playbooks/site.yml',
 'ansible/templates/index.html.j2','ansible/templates/cloudcuyo-security.conf.j2'
]
missing=[p for p in required if not (root/p).is_file()]
if missing: raise SystemExit('Faltan archivos: '+', '.join(missing))
for guide in required[2:4]:
    text=(root/guide).read_text()
    for heading in ['Contexto','Objetivos','Arquitectura','Actividades','Entregables','Limpieza']:
        if heading.lower() not in text.lower():
            raise SystemExit(f'{guide}: falta sección {heading}')
for path in root.rglob('*'):
    if path.is_file() and '.terraform' not in path.parts:
        text=path.read_text(errors='ignore').lower()
        forbidden = [('estrategia ' + '6r'), ('matriz ' + '6r')]
        if any(term in text for term in forbidden):
            raise SystemExit(f'Término no permitido en {path}')
try:
    import yaml
except ImportError:
    print('AVISO: PyYAML no disponible; se omite parseo YAML.')
else:
    for p in [root/'ansible/playbooks/control-node.yml', root/'ansible/playbooks/site.yml', root/'ansible/inventories/lab/group_vars/web.yml']:
        yaml.safe_load(p.read_text())
print('OK: estructura documental y YAML')
PY

if command -v ansible-playbook >/dev/null; then
  (
    cd "$ROOT_DIR/ansible"
    cp -f inventories/lab/hosts.ini.example inventories/lab/hosts.ini
    trap 'rm -f inventories/lab/hosts.ini' EXIT
    ansible-playbook --syntax-check playbooks/control-node.yml
    ansible-playbook --syntax-check playbooks/site.yml
  )
  pass "ansible-playbook --syntax-check"
else
  echo "AVISO: ansible-playbook no está instalado localmente; el syntax-check se ejecutará en el control node."
fi

pass "validación local completa"
