FROM python:3.13.6-alpine3.22

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    DATA_DIR=/app/data \
    HOST=192.168.10.27 \
    PORT=8080 \
    WORKERS=1 \
    LOG_LEVEL=info \
    GENERATE_EVERY_SECONDS=10800 \
    GENERATE_ON_START=true \
    API_KEYS= \
    TAXII_API_ROOT_PATH=/taxii2/root \
    COLLECTION_ID=indicators \
    COLLECTION_TITLE= \
    TAXII_INDICATORS_ONLY=false \
    SOURCE_SYSTEM=

WORKDIR /app

# tini on Alpine installs to /sbin/tini
RUN apk add --no-cache tini curl jq

# Optional but recommended: upgrade pip first
RUN python -m pip install --upgrade pip

COPY requirements.txt /app/

# uvicorn[standard] may need compilers (uvloop, httptools, watchfiles)
# Install build deps, pip install, then remove build deps to keep image slim
RUN apk add --no-cache --virtual .build-deps \
      build-base rust cargo \
    && pip install --no-cache-dir -r /app/requirements.txt \
    && apk del .build-deps

COPY app /app/app
RUN mkdir -p /app/data

EXPOSE 8080

RUN adduser --disabled-password appuser && chown -R appuser /app
USER appuser

ENTRYPOINT ["/sbin/tini", "--"]
CMD ["sh", "-lc", "uvicorn app.main:app --host ${HOST:-0.0.0.0} --port ${PORT:-8080} --workers ${WORKERS:-1} --log-level ${LOG_LEVEL:-info}"]
