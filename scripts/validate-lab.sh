#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
export ANSIBLE_CONFIG="$ROOT_DIR/ansible/ansible.cfg"

fail() {
  printf 'ERROR: %s\n' "$1" >&2
  exit 1
}

require_file() {
  [ -f "$1" ] || fail "falta $1"
}

require_file README.md
require_file guias/guia-cicd-lab01-infra.md
require_file .github/workflows/infra-ci.yml
require_file infra/versions.tf
require_file infra/variables.tf
require_file infra/main.tf
require_file infra/outputs.tf
require_file ansible/ansible.cfg
require_file ansible/requirements.yml
require_file ansible/playbook.yml
require_file ansible/templates/index.html.j2
require_file scripts/render_inventory.py
require_file .devcontainer/devcontainer.json

grep -q 'M3-C4' README.md || fail "README debe identificar M3-C4"
grep -q 'ref=m3-c4-lab' README.md || fail "Codespaces debe abrir m3-c4-lab"
if grep -R -E --exclude-dir=.git --exclude-dir=.terraform --exclude='validate-lab.sh' 'M3-C6|m3-c6' README.md guias infra ansible scripts .github .devcontainer; then
  fail "quedan referencias a la numeración anterior M3-C6"
fi

grep -q 'workflow_dispatch:' .github/workflows/infra-ci.yml || fail "workflow sin workflow_dispatch"
grep -q 'operation:' .github/workflows/infra-ci.yml || fail "workflow sin input operation"
grep -q 'environment: lab' .github/workflows/infra-ci.yml || fail "deploy no usa environment lab"
grep -q 'needs: ci' .github/workflows/infra-ci.yml || fail "deploy debe depender de CI"
grep -q 'permissions:' .github/workflows/infra-ci.yml || fail "workflow sin permissions"
grep -q 'contents: read' .github/workflows/infra-ci.yml || fail "workflow sin contents: read"
grep -q 'cancel-in-progress: false' .github/workflows/infra-ci.yml || fail "concurrency debe evitar cancelar apply/destroy"
grep -q 'actions/checkout@v7' .github/workflows/infra-ci.yml || fail "checkout debe ser v7"
grep -q 'hashicorp/setup-terraform@v4' .github/workflows/infra-ci.yml || fail "setup-terraform debe ser v4"
grep -q 'aws-actions/configure-aws-credentials@v6' .github/workflows/infra-ci.yml || fail "configure-aws-credentials debe ser v6"
grep -q 'TF_VERSION: "1.15.8"' .github/workflows/infra-ci.yml || fail "Terraform del workflow debe ser 1.15.8"
grep -q 'terraform_version:.*env.TF_VERSION' .github/workflows/infra-ci.yml || fail "setup-terraform debe usar TF_VERSION"
grep -q 'init -backend=false' .github/workflows/infra-ci.yml || fail "CI debe usar init -backend=false"
grep -q 'use_lockfile=true' .github/workflows/infra-ci.yml || fail "backend debe activar use_lockfile por CLI"
grep -q 'aws sts get-caller-identity' .github/workflows/infra-ci.yml || fail "deploy debe mostrar identidad AWS"
grep -q 'describe-instance-information' .github/workflows/infra-ci.yml || fail "apply debe esperar registro SSM"
grep -q 'ANSIBLE_CONFIG: ansible/ansible.cfg' .github/workflows/infra-ci.yml || fail "workflow debe cargar ansible.cfg"
grep -q -- '--upgrade ansible-core boto3 botocore' .github/workflows/infra-ci.yml || fail "el runner debe actualizar boto3 y botocore"
grep -q 'version: ">=10.0.0"' ansible/requirements.yml || fail "community.aws debe usar una constraint sin espacios"
grep -q '^remote_tmp = /tmp/.ansible/tmp$' ansible/ansible.cfg || fail "Ansible SSM debe usar remote_tmp escribible"

grep -q 'backend "s3" {}' infra/versions.tf || fail "backend s3 debe estar vacío en código"
grep -q 'AmazonSSMManagedInstanceCore' infra/main.tf || fail "falta policy SSM core"
grep -q 'aws_s3_bucket_server_side_encryption_configuration' infra/main.tf || fail "bucket Ansible debe tener cifrado"
grep -q 'force_destroy = true' infra/main.tf || fail "bucket Ansible debe usar force_destroy"
grep -q 'aws_vpc_security_group_ingress_rule' infra/main.tf || fail "falta regla ingress explícita"
grep -q 'from_port         = 80' infra/main.tf || fail "ingress debe ser HTTP 80"

if grep -R -E --exclude-dir=.git --exclude='validate-lab.sh' 'AKIA[0-9A-Z]{16}' .; then
  fail "posible access key literal encontrada"
fi

if grep -R -E --exclude-dir=.terraform --exclude='validate-lab.sh' 'aws_(lambda|dynamodb|ecr)|api_gateway|key_name|from_port[[:space:]]*=[[:space:]]*22|ansible_connection:[[:space:]]*ssh' infra .github ansible scripts; then
  fail "referencia prohibida encontrada"
fi

if command -v terraform >/dev/null 2>&1; then
  terraform -chdir=infra fmt -check -recursive
  terraform -chdir=infra init -backend=false
  terraform -chdir=infra validate
else
  printf 'WARN: terraform no disponible; se omiten fmt/init/validate\n'
fi

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT
cat > "$tmpdir/tf-outputs.json" <<'JSON'
{
  "instance_id": {"value": "i-0123456789abcdef0", "type": "string"},
  "aws_region": {"value": "us-east-1", "type": "string"},
  "ansible_bucket": {"value": "bp-alumno-1234-ansible-us-east-1", "type": "string"}
}
JSON
python3 scripts/render_inventory.py "$tmpdir/tf-outputs.json" "$tmpdir/inventory.yml"
python3 - <<PY
from pathlib import Path
p = Path('$tmpdir/inventory.yml')
data = p.read_text()
assert 'community.aws.aws_ssm' in data
assert 'i-0123456789abcdef0' in data
assert 'bp-alumno-1234-ansible-us-east-1' in data
PY

if command -v ansible-playbook >/dev/null 2>&1; then
  ansible-playbook --syntax-check ansible/playbook.yml
else
  printf 'WARN: ansible-playbook no disponible; se omite syntax-check\n'
fi

printf 'OK: validación local LAB01 completada\n'
