# Build context: repository root (see docker-compose.yml).

# 1) Flutter PWA. Pinned to the stable channel image; built once per deploy.
FROM ghcr.io/cirruslabs/flutter:stable AS web
WORKDIR /src
COPY mobile/pubspec.yaml mobile/pubspec.lock ./
RUN flutter pub get
COPY mobile/ ./
RUN flutter build web --release --no-web-resources-cdn

# 2) API + worker + scheduler.
FROM python:3.12-slim
ENV PYTHONUNBUFFERED=1 PIP_NO_CACHE_DIR=1
WORKDIR /app
COPY backend/requirements.txt .
RUN pip install -r requirements.txt && playwright install --with-deps chromium \
    && rm -rf /var/lib/apt/lists/*
COPY backend/app ./app
COPY --from=web /src/build/web ./web
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000", "--proxy-headers"]
