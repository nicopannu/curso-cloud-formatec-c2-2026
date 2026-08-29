#!/usr/bin/env bash
set -euo pipefail

root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

required_files=(
  "README.md"
  ".gitignore"
  "terraform/providers.tf"
  "terraform/.terraform.lock.hcl"
  "terraform/variables.tf"
  "terraform/locals.tf"
  "terraform/network.tf"
  "terraform/ec2.tf"
  "terraform/iam.tf"
  "terraform/s3.tf"
  "terraform/outputs.tf"
  "policies/terraform-deploy-policy.json"
  "scripts/popular-s3-desde-local.sh"
  "scripts/validar-estructura.sh"
  "guias/guia-seguridad-lab01-oidc.md"
  "guias/guia-seguridad-lab02-ec2-red-s3.md"
)

for file in "${required_files[@]}"; do
  if [ ! -f "${root_dir}/${file}" ]; then
    printf 'Falta archivo requerido: %s\n' "${file}" >&2
    exit 1
  fi
done

if grep -R --include='*.tf' "aws_db_\|aws_lb\|aws_cloudfront\|aws_key_pair\|aws_s3_object\|aws_s3_bucket_object" "${root_dir}/terraform" >/dev/null; then
  printf 'Se encontro un recurso no permitido para el starter.\n' >&2
  exit 1
fi

credential_scan_files=(
  "${root_dir}/../../.github/workflows/m4-c1-infra-deploy.yml"
  "${root_dir}/../../.github/workflows/m4-c1-oidc-verify.yml"
  "${root_dir}/scripts/popular-s3-desde-local.sh"
)

if grep "AWS_ACCESS_KEY_ID\|AWS_SECRET_ACCESS_KEY" "${credential_scan_files[@]}" >/dev/null; then
  printf 'No se deben usar secretos de access keys en este laboratorio.\n' >&2
  exit 1
fi

deploy_policy="${root_dir}/policies/terraform-deploy-policy.json"

if ! command -v jq >/dev/null 2>&1; then
  printf 'jq es requerido para validar la policy de despliegue.\n' >&2
  exit 1
fi

if ! jq -e '
  .Version == "2012-10-17" and
  (all(.Statement[]; .Resource == "*")) and
  ([.Statement[].Sid] | index("STSIdentity") != null) and
  ([.Statement[].Sid] | index("S3TerraformManagement") != null) and
  ([.Statement[].Sid] | index("EC2TerraformManagement") != null) and
  ([.Statement[].Sid] | index("IAMReadForTerraform") != null) and
  ([.Statement[].Sid] | index("IAMRolesForTerraform") != null) and
  ([.Statement[].Sid] | index("IAMPassRoleToWorkloads") != null) and
  ([.Statement[].Sid] | index("IAMInstanceProfilesForTerraform") != null) and
  ([.Statement[].Sid] | index("IAMManagedPoliciesForTerraform") != null)
' "${deploy_policy}" >/dev/null; then
  printf 'La policy de despliegue no conserva la estructura generica esperada.\n' >&2
  exit 1
fi

if grep -Eq '[0-9]{12}|npannucio|student_identity' "${deploy_policy}"; then
  printf 'La policy de despliegue contiene una cuenta o identidad hardcodeada.\n' >&2
  exit 1
fi

if ! grep -q 'policies/terraform-deploy-policy.json' "${root_dir}/README.md" ||
   ! grep -q 'policies/terraform-deploy-policy.json' "${root_dir}/guias/guia-seguridad-lab02-ec2-red-s3.md"; then
  printf 'README y LAB02 deben referenciar la policy de despliegue.\n' >&2
  exit 1
fi

printf 'Estructura M4-C1 valida.\n'
