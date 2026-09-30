#!/usr/bin/env python3
"""Exercise the payment API and notifier over real local HTTP processes."""

import json
import os
import subprocess
import sys
import time
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

import requests

ROOT = Path(__file__).resolve().parents[1]
PYTHON = sys.executable
children = []


def start(service_dir, port, extra_env):
    env = os.environ.copy()
    env.update({"PORT": str(port), "PYTHONUNBUFFERED": "1", **extra_env})
    proc = subprocess.Popen(
        [PYTHON, str(ROOT / "app" / service_dir / "app.py")],
        cwd=ROOT,
        env=env,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    children.append(proc)
    return proc


def wait_ready(url, proc):
    deadline = time.monotonic() + 20
    while time.monotonic() < deadline:
        if proc.poll() is not None:
            raise RuntimeError(f"Service exited unexpectedly: {url}")
        try:
            if requests.get(url, timeout=0.5).status_code == 200:
                return
        except requests.RequestException:
            pass
        time.sleep(0.2)
    raise TimeoutError(f"Service did not become ready: {url}")


def main():
    notifier = start("notificaciones", 18081, {"NOTIFICATION_DELAY_SECONDS": "0.5"})
    payments_env = {
        "NOTIFICATIONS_URL": "http://127.0.0.1:18081/notify",
        "NOTIFICATION_TIMEOUT_SECONDS": "0",
        "APP_VERSION": "local-e2e",
    }
    payments = start("pagos", 18080, payments_env)
    try:
        wait_ready("http://127.0.0.1:18081/readyz", notifier)
        wait_ready("http://127.0.0.1:18080/readyz", payments)

        with ThreadPoolExecutor(max_workers=4) as pool:
            requests_in_flight = [
                pool.submit(
                    requests.post,
                    "http://127.0.0.1:18080/payments",
                    json={"payment_id": f"e2e-saturation-{i}"},
                    timeout=3,
                )
                for i in range(4)
            ]
            in_flight_peak = 0
            metrics = ""
            deadline = time.monotonic() + 1
            while time.monotonic() < deadline:
                metrics = requests.get("http://127.0.0.1:18080/metrics", timeout=2).text
                gauge_lines = [
                    line for line in metrics.splitlines()
                    if line.startswith('payment_requests_in_flight{service="payments"}')
                ]
                if gauge_lines:
                    in_flight_peak = max(
                        in_flight_peak, int(float(gauge_lines[0].split()[-1]))
                    )
                if in_flight_peak >= 4:
                    break
                time.sleep(0.05)
            assert in_flight_peak >= 4, metrics
            for future in requests_in_flight:
                response = future.result()
                assert response.status_code == 202, response.text

        payments.terminate()
        payments.wait(timeout=5)
        children.remove(payments)
        payments_env["NOTIFICATION_TIMEOUT_SECONDS"] = "0.05"
        payments = start("pagos", 18080, payments_env)
        wait_ready("http://127.0.0.1:18080/readyz", payments)

        degraded = requests.post(
            "http://127.0.0.1:18080/payments",
            json={"payment_id": "e2e-timeout"},
            timeout=3,
        )
        assert degraded.status_code == 202, degraded.text
        assert degraded.json()["payment_status"] == "accepted"
        assert degraded.json()["notification_status"] == "deferred_timeout"

        metrics = requests.get("http://127.0.0.1:18080/metrics", timeout=2).text
        assert 'payment_notification_results_total{result="timeout"} 1.0' in metrics
        assert 'payment_requests_in_flight{service="payments"} 0.0' in metrics

        notifier.terminate()
        notifier.wait(timeout=5)
        children.remove(notifier)
        notifier = start("notificaciones", 18081, {"NOTIFICATION_DELAY_SECONDS": "0"})
        wait_ready("http://127.0.0.1:18081/readyz", notifier)

        recovered = requests.post(
            "http://127.0.0.1:18080/payments",
            json={"payment_id": "e2e-recovered"},
            timeout=3,
        )
        assert recovered.status_code == 202, recovered.text
        assert recovered.json()["notification_status"] == "sent"
        print(json.dumps({"in_flight_peak": in_flight_peak, "timeout_case": degraded.json(), "recovered_case": recovered.json()}, indent=2))
        print("HTTP E2E OK: saturation gauge observed; timeout bounded the wait; request succeeded after recovery.")
    finally:
        for proc in children:
            if proc.poll() is None:
                proc.terminate()
        for proc in children:
            try:
                proc.wait(timeout=5)
            except subprocess.TimeoutExpired:
                proc.kill()
                proc.wait(timeout=5)


if __name__ == "__main__":
    main()
