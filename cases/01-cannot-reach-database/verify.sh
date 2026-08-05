#!/usr/bin/env bash
# Case 01 check. It looks at the end state of the running stack, not at what you
# edited, so any fix that actually works will pass.
set -uo pipefail
cd "$(dirname "$0")"

PORT=5601
fail() { echo "✗ $1"; echo "FAIL: case 01 not solved"; exit 1; }

# 1. Postgres has to be up before anything else is worth checking.
docker compose ps -a --format '{{.Service}}={{.State}}' | grep -q '^postgres=running$' \
  || fail "the postgres container is not running"
echo "✓ postgres container running"

# 2. n8n has to come up AND STAY up, and report itself ready. Readiness, never
#    /healthz. /healthz returns 200 by design even with no database at all.
for _ in $(seq 1 90); do
  state=$(docker compose ps -a --format '{{.Service}}={{.State}}' | grep '^n8n=' | head -1)
  [[ "$state" == "n8n=running" ]] \
    || fail "n8n is not running ($state). Try: docker compose logs --tail=20 n8n"
  code=$(curl -s -o /dev/null -w '%{http_code}' "http://localhost:$PORT/healthz/readiness")
  [[ "$code" == "200" ]] && break
  sleep 2
done
[[ "$code" == "200" ]] || fail "http://localhost:$PORT/healthz/readiness returned $code, expected 200"
echo "✓ n8n container running and ready on http://localhost:$PORT/healthz/readiness"

# 3. And it is really talking to THIS postgres container: its tables are here.
docker compose exec -T postgres psql -U n8n -d n8n -tAc \
  "SELECT to_regclass('public.credentials_entity') IS NOT NULL;" 2>/dev/null | grep -q t \
  || fail "n8n's tables are not in this postgres container"
echo "✓ n8n's schema is present in the postgres container"

echo "PASS: case 01 solved. Open http://localhost:$PORT"
