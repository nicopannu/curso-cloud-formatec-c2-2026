import os
import socket
from flask import Flask, jsonify, request

app = Flask(__name__)
SERVICE_VERSION = os.getenv("SERVICE_VERSION", "swarm-v1")


def local_ips():
    ips = []
    try:
        hostname = socket.gethostname()
        for item in socket.getaddrinfo(hostname, None):
            ip = str(item[4][0])
            if ":" not in ip and ip not in ips:
                ips.append(ip)
    except Exception:
        pass
    return ips


@app.get("/api/payments/health")
def health():
    return jsonify({
        "service": "payment-service",
        "status": "ok",
        "runtime": "docker-swarm",
        "hostname": socket.gethostname(),
        "ips": local_ips(),
        "version": SERVICE_VERSION,
    })


@app.post("/api/payments/checkout")
def checkout():
    payload = request.get_json(silent=True) or {}
    purchase_id = payload.get("purchase_id", "pur-demo")
    amount = int(payload.get("amount", 189999))
    product_name = payload.get("product_name", "Sorny Luma 32")
    return jsonify({
        "backend": "payment-service",
        "runtime": "docker-swarm",
        "hostname": socket.gethostname(),
        "ips": local_ips(),
        "purchase_id": purchase_id,
        "product_name": product_name,
        "amount": amount,
        "payment_url": f"/checkout?pid={purchase_id}&amount={amount}",
        "status": "payment_link_created",
    })


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5004)
