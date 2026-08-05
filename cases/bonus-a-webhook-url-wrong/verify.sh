#!/usr/bin/env bash
# Bonus case A check. It asks the RUNNING instance which public URLs it hands
# out: not what you edited, so any fix that actually works will pass.
set -uo pipefail
cd "$(dirname "$0")"

PORT=5610
JAR=$(mktemp); trap 'rm -f "$JAR"' EXIT
fail() { echo "✗ $1"; echo "FAIL: bonus case A not solved"; exit 1; }

# 1. Readiness on the published port. Never /healthz: it returns 200 by design
#    even with no database, so a green /healthz proves nothing. 200 here also
#    means Postgres is connected and migrated, so it covers both containers.
for _ in $(seq 1 60); do
  code=$(curl -s -o /dev/null -w '%{http_code}' "http://localhost:$PORT/healthz/readiness")
  [[ "$code" == "200" ]] && break; sleep 2
done
[[ "$code" == "200" ]] || fail "http://localhost:$PORT/healthz/readiness returned $code, is the stack up?"
echo "✓ n8n ready on http://localhost:$PORT/healthz/readiness"

# 2. Log in: /rest/settings only reveals the URL fields to an authenticated user.
curl -s -c "$JAR" -o /dev/null -X POST "http://localhost:$PORT/rest/login" \
  -H 'Content-Type: application/json' \
  -d '{"emailOrLdapLoginId":"owner@example.com","password":"DockerLab2026"}'

# 3. The URLs n8n actually hands out. These three fields are exactly what the
#    editor renders on a Webhook node and what executions embed in callbacks.
settings=$(curl -s -b "$JAR" "http://localhost:$PORT/rest/settings")
for field in urlBaseWebhook urlBaseWebhookTest urlBaseEditor; do
  value=$(echo "$settings" | grep -o "\"$field\":\"[^\"]*\"" | cut -d'"' -f4)
  [[ "$value" == *":$PORT"* ]] || fail "$field is \"${value:-<absent, did the login work?>}\", it has to point at port $PORT"
  echo "✓ $field = $value"
done

# 4. And with the current variable, not the deprecated one 2.x warns about.
#    (Captured to a variable on purpose: `docker compose logs | grep -q` closes
#     the pipe early, and under `set -o pipefail` that reads as a failed check.)
logs=$(docker compose logs n8n 2>&1)
[[ "$logs" == *"Use N8N_WEBHOOK_URL instead"* ]] \
  && fail "n8n is warning that one of your variables is deprecated, use the one it names instead"
echo "✓ no deprecated-variable warning on the boot log"

echo "PASS: bonus case A solved. n8n now hands out port $PORT"
