FROM python:3.12-slim

ARG APP_VERSION=local
ENV APP_VERSION=${APP_VERSION} \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

WORKDIR /app
COPY requirements.txt ./requirements.txt
RUN pip install --no-cache-dir --requirement requirements.txt
COPY app.py ./app.py

LABEL org.opencontainers.image.title="pagodigital-pagos" \
      org.opencontainers.image.revision="${APP_VERSION}"

EXPOSE 8000
USER 10001:10001
CMD ["gunicorn", "--bind=0.0.0.0:8000", "--workers=1", "--threads=10", "--timeout=0", "app:app"]
