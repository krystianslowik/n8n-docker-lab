#!/usr/bin/env bash
# Reference stack check. Proves your laptop can run this lab before you are
# asked to debug anything.
set -uo pipefail
cd "$(dirname "$0")"

PORT=5678
EMAIL=owner@example.com
PASSWORD=DockerLab2026
fail() { echo "✗ $1"; echo "FAIL: reference stack is not healthy"; exit 1; }

# 1. Both containers up.
running=$(docker compose ps --status running --format '{{.Service}}' | sort | tr '\n' ' ')
[[ "$running" == *n8n* && "$running" == *postgres* ]] \
  || fail "expected both containers running, got: ${running:-none}"
echo "✓ both containers running"

# 2. Readiness, NOT /healthz, which returns 200 even with a dead database.
for i in $(seq 1 60); do
  code=$(curl -s -o /dev/null -w '%{http_code}' "http://localhost:$PORT/healthz/readiness")
  [[ "$code" == "200" ]] && break
  sleep 2
done
[[ "$code" == "200" ]] || fail "http://localhost:$PORT/healthz/readiness returned $code, expected 200"
echo "✓ n8n ready on http://localhost:$PORT/healthz/readiness"

# 3. The pre-provisioned owner can actually log in.
code=$(curl -s -o /dev/null -w '%{http_code}' -X POST "http://localhost:$PORT/rest/login" \
  -H 'Content-Type: application/json' \
  -d "{\"emailOrLdapLoginId\":\"$EMAIL\",\"password\":\"$PASSWORD\"}")
[[ "$code" == "200" ]] || fail "login as $EMAIL returned $code, expected 200"
echo "✓ owner login works ($EMAIL / $PASSWORD)"

# 4. n8n is really on Postgres, not the SQLite fallback.
docker compose exec -T postgres psql -U n8n -d n8n -tAc \
  "SELECT to_regclass('public.credentials_entity') IS NOT NULL;" 2>/dev/null | grep -q t \
  || fail "n8n's tables are missing from Postgres, is DB_TYPE really postgresdb?"
echo "✓ n8n schema present in Postgres"

echo "PASS: reference stack healthy, open http://localhost:$PORT"
