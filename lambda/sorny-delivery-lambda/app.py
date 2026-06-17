import json
import os
import time
import uuid

REQUIRED_FIELDS = ["purchase_id", "name", "email"]


def lambda_handler(event, context):
    body = parse_body(event)
    missing = [field for field in REQUIRED_FIELDS if not body.get(field)]

    if missing:
        return response(400, {
            "error": "missing_required_fields",
            "fields": missing,
            "backend": "delivery-lambda"
        })

    delivery_id = "del-" + uuid.uuid4().hex[:8]
    record = {
        "event": "delivery_request_received",
        "delivery_id": delivery_id,
        "purchase_id": body["purchase_id"],
        "name": body["name"],
        "email": body["email"],
        "product_name": body.get("product_name", "unknown"),
        "created_at": int(time.time()),
        "runtime": "lambda",
        "stage": os.getenv("STAGE", "lab")
    }

    print(json.dumps(record))

    return response(200, {
        "status": "delivery_pending",
        "delivery_id": delivery_id,
        "message": "Te contactaremos para coordinar el envio",
        "backend": "delivery-lambda"
    })


def parse_body(event):
    if isinstance(event, dict) and "body" in event:
        raw_body = event.get("body") or "{}"
        if isinstance(raw_body, str):
            return json.loads(raw_body)
        if isinstance(raw_body, dict):
            return raw_body
    return event if isinstance(event, dict) else {}


def response(status_code, payload):
    return {
        "statusCode": status_code,
        "headers": {"Content-Type": "application/json"},
        "body": json.dumps(payload)
    }
