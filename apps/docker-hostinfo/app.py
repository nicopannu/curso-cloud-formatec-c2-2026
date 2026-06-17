import os
import socket
from flask import Flask, jsonify

app = Flask(__name__)


def local_ips():
    ips = []
    hostname = socket.gethostname()
    try:
        for info in socket.getaddrinfo(hostname, None, family=socket.AF_INET):
            ip = info[4][0]
            if ip not in ips:
                ips.append(ip)
    except socket.gaierror:
        pass
    return ips


@app.get("/")
def index():
    hostname = socket.gethostname()
    return jsonify({
        "message": "Hola desde Sorny Docker",
        "service": os.getenv("SERVICE_NAME", "sorny-hostinfo"),
        "hostname": hostname,
        "ips": local_ips(),
        "version": os.getenv("APP_VERSION", "v1")
    })


@app.get("/health")
def health():
    return jsonify({"status": "ok", "service": os.getenv("SERVICE_NAME", "sorny-hostinfo")})
