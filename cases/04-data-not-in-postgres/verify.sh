#!/usr/bin/env bash
# Case 04 check. It looks at where the data actually lives, not at what you
# edited, so any fix that really works will pass.
set -uo pipefail
cd "$(dirname "$0")"

PORT=5604
fail() { echo "✗ $1"; echo "FAIL: case 04 not solved"; exit 1; }

# 1. Both containers up.
running=$(docker compose ps --status running --format '{{.Service}}' | sort | tr '\n' ' ')
[[ "$running" == *n8n* && "$running" == *postgres* ]] \
  || fail "expected both containers running, got: ${running:-none}"
echo "✓ both containers running"

# 2. n8n reports itself ready. Readiness, never /healthz. /healthz returns 200
#    by design even with no database at all.
for _ in $(seq 1 90); do
  code=$(curl -s -o /dev/null -w '%{http_code}' "http://localhost:$PORT/healthz/readiness")
  [[ "$code" == "200" ]] && break
  sleep 2
done
[[ "$code" == "200" ]] || fail "http://localhost:$PORT/healthz/readiness returned $code, expected 200"
echo "✓ n8n ready on http://localhost:$PORT/healthz/readiness"

# 3. n8n's schema is in THIS postgres container. This is the check the shipped
#    state fails while everything above it stays green.
docker compose exec -T postgres psql -U n8n -d n8n -tAc \
  "SELECT to_regclass('public.credentials_entity') IS NOT NULL;" 2>/dev/null | grep -q t \
  || fail "postgres holds no n8n tables, n8n is storing its data somewhere else"
echo "✓ n8n's schema is present in the postgres container"

# 4. And n8n is connected to it right now, rather than having been once.
sessions=$(docker compose exec -T postgres psql -U n8n -d n8n -tAc \
  "SELECT count(*) FROM pg_stat_activity WHERE datname='n8n' AND backend_type='client backend' AND pid <> pg_backend_pid();" 2>/dev/null | tr -d '[:space:]')
[[ "${sessions:-0}" -ge 1 ]] || fail "no live client connection to the n8n database (found ${sessions:-none})"
echo "✓ n8n is holding $sessions live connection(s) to the n8n database"

echo "PASS: case 04 solved. Open http://localhost:$PORT"
