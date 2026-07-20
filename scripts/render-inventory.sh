#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TF_DIR="${TF_DIR:-$ROOT_DIR/terraform/ansible-aws-lab}"
OUTPUT_FILE="${OUTPUT_FILE:-$ROOT_DIR/ansible/inventories/lab/hosts.ini}"
MANAGED_KEY_PATH="${MANAGED_KEY_PATH:-~/.ssh/formatec-managed}"

command -v terraform >/dev/null || { echo "ERROR: terraform no está instalado." >&2; exit 1; }
command -v jq >/dev/null || { echo "ERROR: jq no está instalado." >&2; exit 1; }
[[ -f "$TF_DIR/terraform.tfstate" ]] || { echo "ERROR: no existe state local en $TF_DIR." >&2; exit 1; }

outputs="$(terraform -chdir="$TF_DIR" output -json)"
web01="$(jq -er '.managed_private_ips.value.web01' <<<"$outputs")"
web02="$(jq -er '.managed_private_ips.value.web02' <<<"$outputs")"

mkdir -p "$(dirname "$OUTPUT_FILE")"
cat > "$OUTPUT_FILE" <<EOF
[control]
localhost ansible_connection=local

[web]
web01 ansible_host=$web01
web02 ansible_host=$web02

[web:vars]
ansible_user=ubuntu
ansible_ssh_private_key_file=$MANAGED_KEY_PATH
EOF
chmod 0644 "$OUTPUT_FILE"
echo "Inventario generado: $OUTPUT_FILE"
