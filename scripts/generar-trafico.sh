#!/bin/bash
# ─── Generador de tráfico para LAB01 de monitoreo ───
# Uso: ./generar-trafico.sh <FRONTEND_URL> <BACKEND_URL>
# Ej:  ./generar-trafico.sh http://54.1.2.3 http://54.4.5.6:8080

FRONTEND="${1:?Falta URL del frontend}"
BACKEND="${2:?Falta URL del backend}"
DURATION_SECONDS=${3:-300}

echo "Generando tráfico hacia:"
echo "  Frontend: $FRONTEND"
echo "  Backend:  $BACKEND"
echo "  Duración: ${DURATION_SECONDS}s"
echo ""

START=$(date +%s)
ITER=0

while [ $(( $(date +%s) - START )) -lt $DURATION_SECONDS ]; do
  ITER=$((ITER + 1))

  # ── Tráfico normal (cada 2 segundos) ──
  if [ $((ITER % 2)) -eq 0 ]; then
    curl -s -o /dev/null -w "[$(date +%H:%M:%S)] frontend OK  %{http_code}\n" "$FRONTEND/"
    curl -s -X POST "$BACKEND/transferir" \
      -H "Content-Type: application/json" \
      -d '{"monto": 100}' \
      -o /dev/null -w "[$(date +%H:%M:%S)] backend OK  %{http_code}\n"
  fi

  # ── Picos de error (cada ~30 segundos, ~5 requests 500 al frontend) ──
  if [ $((ITER % 30)) -eq 0 ]; then
    echo "[$(date +%H:%M:%S)] >>> PICO DE ERRORES <<<"
    for i in $(seq 1 5); do
      curl -s -o /dev/null -w "[$(date +%H:%M:%S)] frontend 500 %{http_code}\n" "$FRONTEND/server-error"
      sleep 0.2
    done
  fi

  sleep 1
done

echo ""
echo "Tráfico completado: $ITER iteraciones en ${DURATION_SECONDS}s"
