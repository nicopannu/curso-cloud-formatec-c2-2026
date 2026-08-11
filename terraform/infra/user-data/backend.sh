#!/bin/bash
# ─── Backend: Flask API + CloudWatch agent ───
set -e

# Python + Flask
dnf install -y python3 python3-pip
pip3 install flask

mkdir -p /opt/banco-patacon-api

cat > /opt/banco-patacon-api/app.py << 'PYEOF'
import json, logging, sys, time, random
from datetime import datetime, timezone
from flask import Flask, request, jsonify

app = Flask(__name__)

logging.basicConfig(
    stream=sys.stdout,
    level=logging.INFO,
    format='%(message)s'
)
logger = logging.getLogger("banco-patacon-api")

@app.route("/health")
def health():
    return jsonify({"status": "ok"})

@app.route("/transferir", methods=["POST"])
def transferir():
    start = time.time()
    data = request.get_json(silent=True) or {}
    monto = data.get("monto", 0)

    # Simular: ~85% éxito, ~15% error
    if random.random() < 0.15:
        duracion = time.time() - start
        log_entry = json.dumps({
            "timestamp": datetime.now(timezone.utc).isoformat(),
            "endpoint": "transferir",
            "method": "POST",
            "status": "error",
            "reason": "saldo_insuficiente",
            "monto": monto,
            "duration_ms": round(duracion * 1000, 2)
        })
        logger.info(log_entry)
        return jsonify({"status": "error", "reason": "saldo_insuficiente"}), 400

    duracion = time.time() - start
    log_entry = json.dumps({
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "endpoint": "transferir",
        "method": "POST",
        "status": "ok",
        "monto": monto,
        "duration_ms": round(duracion * 1000, 2)
    })
    logger.info(log_entry)
    return jsonify({"id": f"txn-{int(time.time())}", "status": "ok"})

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8080)
PYEOF

# Systemd service
cat > /etc/systemd/system/banco-patacon-api.service << 'UNIT'
[Unit]
Description=Banco Patacon Backend API
After=network.target

[Service]
ExecStart=/usr/bin/python3 /opt/banco-patacon-api/app.py
Restart=always
User=root
WorkingDirectory=/opt/banco-patacon-api
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
UNIT

systemctl daemon-reload
systemctl enable banco-patacon-api --now

# CloudWatch agent
dnf install -y amazon-cloudwatch-agent

cat > /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json << 'CWCONF'
{
  "logs": {
    "logs_collected": {
      "files": {
        "collect_list": [
          {
            "file_path": "/var/log/messages",
            "log_group_name": "/aws/backend/app",
            "log_stream_name": "{instance_id}",
            "timestamp_format": "%b %d %H:%M:%S"
          }
        ]
      }
    }
  }
}
CWCONF

/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
  -a fetch-config \
  -m ec2 \
  -c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json \
  -s
