"""Synthetic payment API used to demonstrate bounded downstream calls."""

import os


import requests
from flask import Flask, jsonify, request
from prometheus_client import CONTENT_TYPE_LATEST, Counter, Gauge, Histogram, generate_latest

app = Flask(__name__)

IN_FLIGHT = Gauge(
    "payment_requests_in_flight",
    "Payment requests currently waiting for the notification dependency",
    ["service"],
)
NOTIFICATION_RESULTS = Counter(
    "payment_notification_results_total",
    "Notification dependency outcomes observed by the payment API",
    ["result"],
)
NOTIFICATION_LATENCY = Histogram(
    "payment_notification_duration_seconds",
    "Time spent waiting for the notification dependency",
    ["service"],
    buckets=(0.05, 0.1, 0.25, 0.5, 1, 2, 5, 10, 30, 60),
)


def _notification_timeout():
    """A value <= 0 reproduces the legacy unbounded-wait behavior for the demo."""
    value = float(os.getenv("NOTIFICATION_TIMEOUT_SECONDS", "1.5"))
    return value if value > 0 else None


@app.get("/healthz")
def healthz():
    return {"status": "ok"}, 200


@app.get("/readyz")
def readyz():
    return {"status": "ready"}, 200


@app.get("/version")
def version():
    return {"version": os.getenv("APP_VERSION", "local")}, 200


@app.get("/metrics")
def metrics():
    return generate_latest(), 200, {"Content-Type": CONTENT_TYPE_LATEST}


@app.post("/payments")
def create_payment():
    """Accept a synthetic payment even if its optional email notification fails."""
    payload = request.get_json(silent=True) or {}
    payment_id = str(payload.get("payment_id", "demo-payment"))
    notification_url = os.getenv(
        "NOTIFICATIONS_URL", "http://127.0.0.1:8081/notify"
    )
    notification_status = "sent"
    IN_FLIGHT.labels(service="payments").inc()
    try:
        with NOTIFICATION_LATENCY.labels(service="payments").time():
            response = requests.post(
                notification_url,
                json={"payment_id": payment_id},
                timeout=_notification_timeout(),
            )
            response.raise_for_status()
    except requests.exceptions.Timeout:
        notification_status = "deferred_timeout"
        NOTIFICATION_RESULTS.labels(result="timeout").inc()
    except requests.exceptions.RequestException:
        notification_status = "deferred_error"
        NOTIFICATION_RESULTS.labels(result="error").inc()
    else:
        NOTIFICATION_RESULTS.labels(result="sent").inc()
    finally:
        IN_FLIGHT.labels(service="payments").dec()

    return jsonify(
        payment_id=payment_id,
        payment_status="accepted",
        notification_status=notification_status,
    ), 202


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=int(os.getenv("PORT", "8000")), threaded=True)
