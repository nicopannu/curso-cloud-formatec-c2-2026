#!/usr/bin/env bash
set -euo pipefail

ENDPOINT="${1:?Indicá endpoint RDS}"
PORT="${2:-5432}"
SECRET_ARN="${3:?Indicá ARN del secreto RDS}"
REGION="${AWS_REGION:-us-east-1}"
DB_NAME="${DB_NAME:-securitylab}"

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

printf 'Inicializando tabla lab_access con conexión TLS. La contraseña no se imprime.\n'
PGPASSWORD="$DB_PASSWORD" psql \
  "host=${ENDPOINT} port=${PORT} dbname=${DB_NAME} user=${DB_USER} sslmode=require" \
  -v ON_ERROR_STOP=1 \
  -c "CREATE TABLE IF NOT EXISTS lab_access (id integer PRIMARY KEY, mensaje text NOT NULL);" \
  -c "INSERT INTO lab_access (id, mensaje) VALUES (1, 'dato de prueba del laboratorio') ON CONFLICT (id) DO UPDATE SET mensaje = EXCLUDED.mensaje;"
printf 'Inicialización completada.\n'
