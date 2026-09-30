#!/usr/bin/env bash
set -euo pipefail

DEMO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PAYMENTS_IMAGE="${PAYMENTS_IMAGE:-pagodigital-pagos:demo}"
NOTIFICATIONS_IMAGE="${NOTIFICATIONS_IMAGE:-pagodigital-notificaciones:demo}"
APP_VERSION="${APP_VERSION:-local}"
NOTIFICATION_TIMEOUT_SECONDS="${NOTIFICATION_TIMEOUT_SECONDS:-1.5}"

command -v envsubst >/dev/null || { echo "Falta envsubst (gettext-base)" >&2; exit 1; }
command -v kubectl >/dev/null || { echo "Falta kubectl" >&2; exit 1; }

export PAYMENTS_IMAGE NOTIFICATIONS_IMAGE APP_VERSION NOTIFICATION_TIMEOUT_SECONDS
kubectl apply -f "$DEMO_DIR/k8s/namespace.yaml"
envsubst '${PAYMENTS_IMAGE} ${NOTIFICATIONS_IMAGE} ${APP_VERSION} ${NOTIFICATION_TIMEOUT_SECONDS}' \
  < "$DEMO_DIR/k8s/workloads.yaml.tpl" > /tmp/tp-final-ej3-workloads.yaml
kubectl apply -f /tmp/tp-final-ej3-workloads.yaml
kubectl apply -f "$DEMO_DIR/k8s/prometheus.yaml"
kubectl rollout status deployment/pagos-api -n tp-final-ej3 --timeout=5m
kubectl rollout status deployment/notificaciones -n tp-final-ej3 --timeout=5m
kubectl rollout status deployment/prometheus -n tp-final-ej3 --timeout=5m

echo "Demo disponible en namespace tp-final-ej3"
