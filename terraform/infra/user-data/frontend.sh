#!/bin/bash
# ─── Frontend: nginx + CloudWatch agent ───
set -e

# Nginx
dnf install -y nginx

# Contrato estable para CloudWatch Logs y el metric filter de errores 5xx.
cat > /etc/nginx/conf.d/cloudcuyo-log.conf << 'NGXLOG'
log_format cloudcuyo '$remote_addr - $remote_user [$time_local] "$request" '
                     '$status $body_bytes_sent "$http_referer" "$http_user_agent"';
access_log /var/log/nginx/access.log cloudcuyo;
NGXLOG

cat > /usr/share/nginx/html/index.html << 'HTML'
<!doctype html>
<html lang="es">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Banco Patacon</title>
  <style>
    body { font-family: system-ui; max-width: 600px; margin: 80px auto; padding: 0 20px; background: #0a0f1e; color: #e0e6f0; }
    h1 { color: #24F49F; font-size: 2em; }
    .status { background: #11202F; padding: 24px; border-radius: 12px; border: 1px solid #1E3A52; margin: 20px 0; }
    .status .ok { color: #24F49F; font-weight: bold; }
    footer { margin-top: 40px; font-size: 0.85em; color: #8FA3BD; }
  </style>
</head>
<body>
  <h1>Banco Patacon</h1>
  <div class="status">
    <p><span class="ok">●</span> Canal de transferencias disponible</p>
    <p>Todas las operaciones funcionan con normalidad.</p>
  </div>
  <footer>Banco Patacon — C2 2026 &middot; Monitoreo proactivo</footer>
</body>
</html>
HTML

systemctl enable nginx --now

# Endpoint que genera 500 para pruebas de monitoreo
cat > /etc/nginx/default.d/error.conf << 'NGXERR'
location /server-error {
    return 500 "Error interno simulado para pruebas de monitoreo";
}
NGXERR
systemctl reload nginx

# CloudWatch agent
dnf install -y amazon-cloudwatch-agent

cat > /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json << 'CWCONF'
{
  "logs": {
    "logs_collected": {
      "files": {
        "collect_list": [
          {
            "file_path": "/var/log/nginx/access.log",
            "log_group_name": "/aws/frontend/access",
            "log_stream_name": "{instance_id}",
            "timestamp_format": "%d/%b/%Y:%H:%M:%S %z"
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
