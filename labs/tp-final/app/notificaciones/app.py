"""Synthetic email-notification dependency with controllable latency."""

import os
import time

from flask import Flask, jsonify, request

app = Flask(__name__)


@app.get("/healthz")
def healthz():
    return {"status": "ok"}, 200


@app.get("/readyz")
def readyz():
    return {"status": "ready"}, 200


@app.post("/notify")
def notify():
    payload = request.get_json(silent=True) or {}
    delay = max(0.0, float(os.getenv("NOTIFICATION_DELAY_SECONDS", "0")))
    if delay:
        time.sleep(delay)
    return jsonify(
        result="accepted",
        payment_id=str(payload.get("payment_id", "unknown")),
        simulated_delay_seconds=delay,
    ), 202


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=int(os.getenv("PORT", "8080")), threaded=True)
