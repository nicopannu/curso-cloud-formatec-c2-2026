#!/usr/bin/env bash
set -euo pipefail

ENDPOINT="${1:?Indicá endpoint RDS}"
PORT="${2:-5432}"
SECRET_ARN="${3:?Indicá ARN del secreto RDS}"
REGION="${AWS_REGION:-us-east-1}"
DB_NAME="${DB_NAME:-securitylab}"

printf '== Identidad AWS ==\n'
aws sts get-caller-identity --region "$REGION" --output json

printf '\n== Alcance TCP a RDS ==\n'
if timeout 5 bash -c "</dev/tcp/${ENDPOINT}/${PORT}"; then
  printf 'TCP_REACHABLE\n'
else
  printf 'TCP_BLOCKED_OR_UNREACHABLE\n'
  printf 'No se consulta Secrets Manager cuando la red ya bloquea el acceso.\n'
  exit 0
fi

printf '\n== Recuperar secreto autorizado ==\n'
SECRET_JSON="$(aws secretsmanager get-secret-value \
  --secret-id "$SECRET_ARN" \
  --region "$REGION" \
  --query SecretString \
  --output text)"

DB_USER="$(jq -r '.username' <<<"$SECRET_JSON")"
DB_PASSWORD="$(jq -r '.password' <<<"$SECRET_JSON")"

if [[ -z "$DB_USER" || "$DB_USER" == "null" || -z "$DB_PASSWORD" || "$DB_PASSWORD" == "null" ]]; then
  printf 'SECRET_FORMAT_INVALID\n' >&2
  exit 1
fi
printf 'SECRET_RETRIEVED_WITHOUT_PRINTING_PASSWORD\n'

printf '\n== Leer dato de prueba con TLS ==\n'
PGPASSWORD="$DB_PASSWORD" psql \
  "host=${ENDPOINT} port=${PORT} dbname=${DB_NAME} user=${DB_USER} sslmode=require" \
  -v ON_ERROR_STOP=1 \
  -Atc 'SELECT id, mensaje FROM lab_access ORDER BY id;'
