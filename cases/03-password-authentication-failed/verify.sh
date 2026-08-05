#!/usr/bin/env bash
# Case 03 check. Reads the real end state of the stack, not your diff.
set -uo pipefail
cd "$(dirname "$0")"

PORT=5603
fail() { echo "✗ $1"; echo "FAIL: case 03 is not solved"; exit 1; }

# 1. Both containers actually running. n8n giving up and exiting is the symptom.
running=$(docker compose ps --status running --format '{{.Service}}' | sort | tr '\n' ' ')
[[ "$running" == *n8n* && "$running" == *postgres* ]] \
  || fail "expected both containers running, got: ${running:-none}"
echo "✓ both containers running"

# 2. Readiness, NOT /healthz. /healthz returns 200 even with a dead database.
#    Generous loop: the first successful boot runs the whole migration chain.
for _ in $(seq 1 90); do
  code=$(curl -s -o /dev/null -w '%{http_code}' "http://localhost:$PORT/healthz/readiness")
  [[ "$code" == "200" ]] && break
  docker compose ps --status running --format '{{.Service}}' | grep -qx n8n || break
  sleep 2
done
[[ "$code" == "200" ]] \
  || fail "readiness returned $code, n8n is: $(docker compose ps -a --format '{{.Status}}' n8n)"
echo "✓ n8n ready on http://localhost:$PORT/healthz/readiness"

# 3. It really did authenticate and migrate: n8n's tables exist in Postgres.
docker compose exec -T postgres psql -U n8n -d n8n -tAc \
  "SELECT to_regclass('public.credentials_entity') IS NOT NULL;" 2>/dev/null | grep -q t \
  || fail "n8n's tables are missing from Postgres, it never got in"
echo "✓ n8n schema present in Postgres"

echo "PASS: case 03 solved"
