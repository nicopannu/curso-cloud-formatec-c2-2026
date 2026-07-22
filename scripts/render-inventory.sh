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
managed_nodes="$(jq -er '
  .managed_private_ips.value
  | to_entries
  | sort_by(.key)
  | .[]
  | "\(.key) ansible_host=\(.value)"
' <<<"$outputs")"
[[ -n "$managed_nodes" ]] || { echo "ERROR: managed_private_ips no contiene nodos." >&2; exit 1; }

mkdir -p "$(dirname "$OUTPUT_FILE")"
cat > "$OUTPUT_FILE" <<EOF
[control]
localhost ansible_connection=local

[web]
$managed_nodes

[web:vars]
ansible_user=ubuntu
ansible_ssh_private_key_file=$MANAGED_KEY_PATH
EOF
chmod 0644 "$OUTPUT_FILE"
echo "Inventario generado: $OUTPUT_FILE"
