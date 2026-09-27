# Build context: repository root (see docker-compose.yml).

# 1) Flutter PWA. Pinned Flutter version (Dart 3.12) so builds are reproducible.
FROM ghcr.io/cirruslabs/flutter:3.44.0 AS web
WORKDIR /src
COPY mobile/pubspec.yaml mobile/pubspec.lock ./
RUN flutter pub get
COPY mobile/ ./
# --wasm: Skia/WebAssembly renderer where supported (smoother), automatic JS fallback elsewhere.
RUN flutter build web --release --wasm --no-web-resources-cdn \
    && find build/web -type f \( -name '*.wasm' -o -name '*.js' -o -name '*.mjs' -o -name '*.json' \
       -o -name '*.otf' -o -name '*.ttf' -o -name '*.html' -o -name '*.symbols' \) -exec gzip -9 -k {} \;

# 2) API + worker + scheduler.
# Debian 12 (bookworm): supported by Playwright; Chromium 140 renders Persian ZWNJ correctly.
FROM python:3.12-slim-bookworm
ENV PYTHONUNBUFFERED=1 PIP_NO_CACHE_DIR=1
WORKDIR /app
COPY backend/requirements.txt .
RUN pip install -r requirements.txt && playwright install --with-deps chromium \
    && rm -rf /var/lib/apt/lists/*
COPY backend/app ./app
COPY --from=web /src/build/web ./web
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000", "--proxy-headers"]
