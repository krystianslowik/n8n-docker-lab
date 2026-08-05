#!/usr/bin/env bash
# bonus-b check: n8n is healthy AND can actually reach the metrics API by name.
set -uo pipefail
cd "$(dirname "$0")"

PORT=5611
TARGET=metrics-api
fail() { echo "✗ $1"; echo "FAIL: bonus-b not solved"; exit 1; }

# 1. n8n and postgres are up.
running=$(docker compose ps --status running --format '{{.Service}}' | sort | tr '\n' ' ')
[[ "$running" == *n8n* && "$running" == *postgres* ]] \
  || fail "expected n8n and postgres running, got: ${running:-none}"
echo "✓ n8n and postgres running"

# 2. The third service is up somewhere on this machine. It never was the
#    problem, but check anyway, and deliberately without caring which
#    Compose project owns it.
[[ -n "$(docker ps --filter "name=$TARGET" --filter status=running -q)" ]] \
  || fail "no running $TARGET container found, run ./setup.sh"
echo "✓ $TARGET running"

# 3. Readiness, not /healthz. /healthz returns 200 even with a dead database.
for _ in $(seq 1 60); do
  code=$(curl -s -o /dev/null -w '%{http_code}' "http://localhost:$PORT/healthz/readiness")
  [[ "$code" == "200" ]] && break
  sleep 2
done
[[ "$code" == "200" ]] || fail "http://localhost:$PORT/healthz/readiness returned $code, expected 200"
echo "✓ n8n ready on http://localhost:$PORT/healthz/readiness"

# 4. The actual end state: n8n resolves AND reaches the third service by name.
out=$(docker compose exec -T n8n wget -T 5 -O /dev/null "http://$TARGET/" 2>&1) \
  || fail "n8n cannot reach http://$TARGET/, $(echo "$out" | tr '\n' ' ' | tail -c 120)"
echo "✓ n8n reached http://$TARGET/ from inside its own container"

echo "PASS: bonus-b solved"
