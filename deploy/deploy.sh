#!/usr/bin/env bash
# Deploy Postyar to a shared server from your machine.
#
#   ./deploy/deploy.sh                 # defaults: HOST=infivita PORT=8200
#   HOST=myserver PORT=5100 ./deploy/deploy.sh
#   LLM_API_KEY=... ./deploy/deploy.sh # also sets/replaces the text-model key in the server .env
#   CADDY_NETWORK=<net> ./deploy/deploy.sh  # also attach the API to the reverse proxy's docker network
#
# The API listens on 127.0.0.1:PORT on the server (not public). Public access goes through the
# existing reverse proxy (HTTPS on 443) once a site block for Postyar is added there.
#
# Safety rules this script follows:
# - touches only /opt/postyar on the server and its own compose project "postyar"
# - never binds 80/443, never edits Caddy, never prunes, never stops other containers
# - refuses to run if the chosen port is used by something that isn't ours
# - secrets live only in /opt/postyar/.env on the server (created once, never overwritten)
set -euo pipefail

HOST="${HOST:-infivita}"
NAME="postyar"
PORT="${PORT:-8200}"
DIR="/opt/${NAME}"
IP="${IP:-169.58.112.63}"

cd "$(dirname "$0")/.."

case "$PORT" in 22|53|80|443|1080|2053|2081|4443|8095|8098|8181|8443)
  echo "Port $PORT is reserved on this server; pick another (e.g. 8200, 5100, 3100)." >&2; exit 1;;
esac

echo "==> 1/5 Preflight on $HOST (read-only)"
ssh "$HOST" bash -s -- "$DIR" "$PORT" "$NAME" <<'REMOTE'
set -euo pipefail
DIR=$1; PORT=$2; NAME=$3
if [ -e "$DIR" ] && [ ! -f "$DIR/docker-compose.yml" ]; then
  echo "ABORT: $DIR exists but is not a Postyar checkout." >&2; exit 1
fi
if ss -lnt | awk '{print $4}' | grep -Eq "[:.]${PORT}\$"; then
  if ! docker ps --filter "label=com.docker.compose.project=${NAME}" --format '{{.Ports}}' | grep -q ":${PORT}->"; then
    echo "ABORT: port ${PORT} is already used by another service." >&2; exit 1
  fi
  echo "port ${PORT} is ours (redeploy)"
else
  echo "port ${PORT} is free"
fi
free -m | awk 'NR<=2'
df -h /opt | awk 'NR==2 {print "disk free on /opt: " $4}'
REMOTE

echo "==> 2/5 Sync code to $HOST:$DIR"
ssh "$HOST" "mkdir -p '$DIR'"
rsync -az --delete \
  --exclude '.git/' --exclude '.env' --exclude '__pycache__/' --exclude '.pytest_cache/' \
  --exclude 'mobile/build/' --exclude 'mobile/.dart_tool/' --exclude 'mobile/.idea/' \
  ./ "$HOST:$DIR/"

echo "==> 3/5 Server .env (created once with random secrets; never overwritten)"
ssh "$HOST" bash -s -- "$DIR" "$PORT" <<'REMOTE'
set -euo pipefail
DIR=$1; PORT=$2
cd "$DIR"
if [ ! -f .env ]; then
  cp .env.example .env
  sed -i "s|^ADMIN_TOKEN=.*|ADMIN_TOKEN=$(openssl rand -hex 24)|" .env
  sed -i "s|^SECRET_KEY=.*|SECRET_KEY=$(openssl rand -hex 32)|" .env
  sed -i "s|^POSTGRES_PASSWORD=.*|POSTGRES_PASSWORD=$(openssl rand -hex 16)|" .env
  chmod 600 .env
  echo "created $DIR/.env  (add LLM_API_KEY there to enable generation)"
fi
grep -q '^POSTYAR_BIND=' .env || echo 'POSTYAR_BIND=127.0.0.1' >> .env
grep -q '^POSTYAR_PORT=' .env || echo "POSTYAR_PORT=${PORT}" >> .env
REMOTE

if [ -n "${LLM_API_KEY:-}" ]; then
  # Sent over stdin so the key never appears in a command line or in the repo.
  printf '%s\n' "$LLM_API_KEY" | ssh "$HOST" "cd '$DIR' && read -r K && \
    { grep -v '^LLM_API_KEY=' .env; echo \"LLM_API_KEY=\$K\"; } > .env.tmp && mv .env.tmp .env && chmod 600 .env && echo 'LLM_API_KEY set'"
fi

if [ -n "${CADDY_NETWORK:-}" ]; then
  ssh "$HOST" bash -s -- "$DIR" "$CADDY_NETWORK" <<'REMOTE'
set -euo pipefail
DIR=$1; NET=$2
docker network inspect "$NET" >/dev/null || { echo "ABORT: docker network $NET not found" >&2; exit 1; }
cd "$DIR"
grep -v -e '^CADDY_NETWORK=' -e '^COMPOSE_FILE=' .env > .env.tmp
{ cat .env.tmp; echo "CADDY_NETWORK=$NET"; echo "COMPOSE_FILE=docker-compose.yml:deploy/caddy-network.yml"; } > .env
rm .env.tmp; chmod 600 .env
echo "API will join network $NET as postyar-api-1:8000"
REMOTE
fi

echo "==> 4/5 Build and start (compose project: $NAME)"
ssh "$HOST" "cd '$DIR' && docker compose -p '$NAME' up -d --build"

echo "==> 5/5 Verify"
sleep 8
ssh "$HOST" "docker ps --filter 'label=com.docker.compose.project=$NAME' --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'"
echo -n "app health (on server): "; ssh "$HOST" "curl -s -m 15 http://127.0.0.1:$PORT/health" || echo "(no answer yet)"; echo
echo -n "app page   (on server): "; ssh "$HOST" "curl -s -m 15 -o /dev/null -w '%{http_code}' http://127.0.0.1:$PORT/"; echo
echo -n "other projects (must be 200): "; curl -s -m 15 -o /dev/null -w "%{http_code}\n" "https://169-58-112-63.sslip.io/app/"
echo
echo "Folder: $DIR"
echo "Local:  http://127.0.0.1:$PORT/ on the server (public HTTPS needs a reverse-proxy site block)"
