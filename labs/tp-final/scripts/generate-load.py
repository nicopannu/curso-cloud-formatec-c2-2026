#!/usr/bin/env python3
"""Generate bounded concurrent synthetic traffic for the demo."""

import argparse
import json
import threading
import time
import urllib.error
import urllib.request
from concurrent.futures import ThreadPoolExecutor


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--url", default="http://127.0.0.1:18080/payments")
    parser.add_argument("--concurrency", type=int, default=12)
    parser.add_argument("--duration", type=int, default=75)
    parser.add_argument("--request-timeout", type=float, default=60)
    args = parser.parse_args()
    if args.concurrency < 1 or args.duration < 1:
        parser.error("concurrency and duration must be positive")

    stop_at = time.monotonic() + args.duration
    counts = {"202": 0, "other": 0, "timeout_or_error": 0}
    lock = threading.Lock()

    def worker(worker_id):
        sequence = 0
        while time.monotonic() < stop_at:
            sequence += 1
            payload = json.dumps({"payment_id": f"demo-{worker_id}-{sequence}"}).encode()
            request = urllib.request.Request(
                args.url,
                data=payload,
                headers={"Content-Type": "application/json"},
                method="POST",
            )
            try:
                with urllib.request.urlopen(request, timeout=args.request_timeout) as response:
                    key = "202" if response.status == 202 else "other"
            except (TimeoutError, urllib.error.URLError, OSError):
                key = "timeout_or_error"
            with lock:
                counts[key] += 1

    print(f"Enviando tráfico por {args.duration}s, concurrencia={args.concurrency}, destino={args.url}", flush=True)
    with ThreadPoolExecutor(max_workers=args.concurrency) as pool:
        futures = [pool.submit(worker, i) for i in range(args.concurrency)]
        for future in futures:
            future.result()
    print(json.dumps(counts, indent=2))


if __name__ == "__main__":
    main()
