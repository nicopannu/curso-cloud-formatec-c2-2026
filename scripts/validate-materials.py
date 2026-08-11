#!/usr/bin/env python3
from __future__ import annotations

import csv
from datetime import datetime, timedelta
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

REQUIRED = {
    "README.md": ["M3-C5", "Monitoreo proactivo", "Alcance de la práctica"],
    "guias/guia-monitoreo-lab01-banco-patacon.md": [
        "## Contexto",
        "## Objetivos",
        "## Alcance obligatorio",
        "## Entregables",
        "## Criterios de evaluación",
    ],
    "material-docente/m3-c5-guion-clase.md": ["## Agenda de 90 minutos", "## Scope cuts"],
    "material-docente/m3-c5-slides-outline.md": ["## Slide 1", "## Slide 15"],
    "plantillas/matriz-sli-slo-alertas.md": ["## 2. SLI y SLO", "## 4. Alertas accionables"],
    "datos/incidente-banco-patacon.csv": [],
}

FORBIDDEN = ("Estrategia 6R", "matriz 6R")
FORBIDDEN_STUDENT_LABELS = {
    "degradation_begins",
    "error_rate_alarm",
    "users_affected",
    "investigation",
    "recovery",
    "recovered",
    "stable",
}


def validate_files() -> None:
    for relative, markers in REQUIRED.items():
        path = ROOT / relative
        if not path.is_file():
            raise SystemExit(f"FALTA: {relative}")
        text = path.read_text(encoding="utf-8")
        for marker in markers:
            if marker not in text:
                raise SystemExit(f"FALTA MARCADOR en {relative}: {marker}")
        for term in FORBIDDEN:
            if term.lower() in text.lower():
                raise SystemExit(f"TÉRMINO NO PERMITIDO en {relative}: {term}")


def parse_timestamp(value: str) -> datetime:
    try:
        return datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError as exc:
        raise SystemExit(f"CSV: timestamp inválido: {value}") from exc


def validate_dataset() -> None:
    path = ROOT / "datos/incidente-banco-patacon.csv"
    with path.open(encoding="utf-8", newline="") as stream:
        reader = csv.DictReader(stream)
        rows = list(reader)
        fields = set(reader.fieldnames or [])

    expected_fields = {
        "window_start_utc",
        "requests",
        "http_5xx",
        "latency_p95_ms",
        "cpu_avg_percent",
        "memory_avg_percent",
        "change_event",
    }
    if fields != expected_fields:
        raise SystemExit("CSV: columnas inválidas")
    if len(rows) != 12:
        raise SystemExit(f"CSV: se esperaban 12 ventanas y hay {len(rows)}")

    timestamps: list[datetime] = []
    rates: list[float] = []
    events: list[str] = []
    for row in rows:
        timestamps.append(parse_timestamp(row["window_start_utc"]))
        requests = int(row["requests"])
        errors = int(row["http_5xx"])
        latency = int(row["latency_p95_ms"])
        cpu = int(row["cpu_avg_percent"])
        memory = int(row["memory_avg_percent"])
        event = row["change_event"].strip()
        if requests <= 0 or not 0 <= errors <= requests:
            raise SystemExit("CSV: requests/http_5xx inválidos")
        if latency <= 0 or not 0 <= cpu <= 100 or not 0 <= memory <= 100:
            raise SystemExit("CSV: latencia o porcentajes inválidos")
        if event in FORBIDDEN_STUDENT_LABELS:
            raise SystemExit(f"CSV: etiqueta que revela la solución: {event}")
        if event and not (event.startswith("deploy_sha_") or event.startswith("rollback_sha_")):
            raise SystemExit(f"CSV: evento de cambio no permitido: {event}")
        rates.append(errors / requests)
        events.append(event)

    if len(set(timestamps)) != len(timestamps):
        raise SystemExit("CSV: timestamps duplicados")
    for previous, current in zip(timestamps, timestamps[1:]):
        if current - previous != timedelta(minutes=5):
            raise SystemExit("CSV: la cadencia debe ser de cinco minutos")

    peak = rows[rates.index(max(rates))]
    if peak["window_start_utc"] != "2026-08-05T09:30:00Z":
        raise SystemExit("CSV: el pico esperado de tasa 5xx cambió")
    if sum(event.startswith("deploy_sha_") for event in events) != 1:
        raise SystemExit("CSV: se esperaba un único evento de deploy")
    if sum(event.startswith("rollback_sha_") for event in events) != 1:
        raise SystemExit("CSV: se esperaba un único evento de rollback")


def main() -> None:
    validate_files()
    validate_dataset()
    print("OK: materiales M3-C5 validados")


if __name__ == "__main__":
    main()
