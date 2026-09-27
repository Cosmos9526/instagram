#!/usr/bin/env bash
# Update Postyar on the server from GitHub main. Touches only /opt/postyar and the "postyar" compose project.
# Run by the GitHub Actions deploy workflow through a restricted SSH key (see deploy/README.md).
set -euo pipefail
cd /opt/postyar
git fetch --quiet origin main
if [ "$(git rev-parse HEAD)" = "$(git rev-parse origin/main)" ] && [ "${FORCE:-0}" != "1" ]; then
  echo "already up to date: $(git rev-parse --short HEAD)"
else
  git merge --ff-only --quiet origin/main
  # settings introduced by newer versions (added once, never overwritten)
  grep -q '^LLM_FALLBACK_URL=' .env || echo 'LLM_FALLBACK_URL=https://text.pollinations.ai/openai' >> .env
  grep -q '^RESEARCH_PROVIDER=' .env && sed -i 's/^RESEARCH_PROVIDER=gemini$/RESEARCH_PROVIDER=free/' .env
  sed -i 's/^IMAGE_PROVIDER=none$/IMAGE_PROVIDER=pollinations/' .env
  docker compose -p postyar up -d --build --remove-orphans
  docker image prune -f --filter "label=com.docker.compose.project=postyar" >/dev/null 2>&1 || true
fi
sleep 8
docker ps --filter label=com.docker.compose.project=postyar --format "{{.Names}}  {{.Status}}"
echo -n "health: "; curl -s -m 10 localhost:8200/health; echo
echo -n "other project (must be 200): "; curl -s -o /dev/null -w "%{http_code}\n" https://169-58-112-63.sslip.io/app/
echo "deployed: $(git log -1 --format='%h %s')"
