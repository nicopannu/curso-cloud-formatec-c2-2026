import os
import time
import uuid
import socket
import requests
from flask import Flask, jsonify, request

app = Flask(__name__)
PAYMENT_URL = os.getenv("PAYMENT_URL", "http://payment-service:5004/api/payments/checkout")
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


@app.get("/api/purchases/health")
def health():
    return jsonify({
        "service": "purchase-service",
        "status": "ok",
        "runtime": "docker-swarm",
        "hostname": socket.gethostname(),
        "ips": local_ips(),
        "version": SERVICE_VERSION,
    })


@app.post("/api/purchases")
def create_purchase():
    payload = request.get_json(silent=True) or {}
    product_name = payload.get("product_name", "Sorny Luma 32")
    amount = int(payload.get("amount", 189999))
    purchase_id = payload.get("purchase_id", f"pur-{uuid.uuid4().hex[:8]}")

    payment_payload = {
        "purchase_id": purchase_id,
        "product_name": product_name,
        "amount": amount,
    }

    started = time.time()
    payment_response = None
    payment_error = None
    try:
        response = requests.post(PAYMENT_URL, json=payment_payload, timeout=3)
        payment_response = response.json()
    except Exception as exc:
        payment_error = str(exc)

    result = {
        "status": "purchase_created",
        "purchase_id": purchase_id,
        "product_name": product_name,
        "amount": amount,
        "backend": "purchase-service",
        "runtime": "docker-swarm",
        "hostname": socket.gethostname(),
        "ips": local_ips(),
        "payment_url_used": PAYMENT_URL,
        "elapsed_ms": round((time.time() - started) * 1000, 2),
    }
    if payment_response:
        result["payment"] = payment_response
    if payment_error:
        result["payment_error"] = payment_error
        result["status"] = "purchase_created_payment_pending"
    return jsonify(result), 201


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5003)
