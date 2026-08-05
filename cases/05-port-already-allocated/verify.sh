#!/usr/bin/env bash
# Case 05 check. Reads the real end state of the stack, never your edits.
set -uo pipefail
cd "$(dirname "$0")"

PORT=5605
fail() { echo "✗ $1"; echo "FAIL: case 05 not solved"; exit 1; }

# 1. All three of the customer's services are running.
running=$(docker compose ps --status running --format '{{.Service}}' | sort | tr '\n' ' ')
for svc in adminer n8n postgres; do
  [[ "$running" == *"$svc"* ]] || fail "'$svc' is not running (running: ${running:-none})"
done
echo "✓ all three services running: $running"

# 2. Each service that needs the host has its own slice of it.
n8n_pub=$(docker compose port n8n 5678 2>/dev/null | head -1)
adm_pub=$(docker compose port adminer 8080 2>/dev/null | head -1)
[[ "${n8n_pub##*:}" == "$PORT" ]] \
  || fail "n8n is not published on host port $PORT (it is on: ${n8n_pub:-nothing}). If you just edited compose.yaml, re-run ./setup.sh"
[[ -n "$adm_pub" && "${adm_pub##*:}" != "$PORT" && "${adm_pub##*:}" != "0" ]] \
  || fail "adminer is published on: ${adm_pub:-nothing}, the data team needs it in a browser, on a port of its own"
echo "✓ n8n published on host $PORT, adminer on host ${adm_pub##*:}"

# 3. What answers on $PORT is n8n, and it is ready. Readiness, not /healthz:
#    /healthz returns 200 even with a dead database, and any web server will
#    happily return 200 for a path it has never heard of.
for _ in $(seq 1 90); do
  body=$(curl -s -m 3 "http://localhost:$PORT/healthz/readiness")
  [[ "$body" == *'"status":"ok"'* ]] && break
  sleep 2
done
[[ "$body" == *'"status":"ok"'* ]] \
  || fail "http://localhost:$PORT/healthz/readiness never answered as n8n (last reply: $(echo "$body" | tr -d '\n' | head -c 50))"
echo "✓ n8n ready on http://localhost:$PORT/healthz/readiness"

# 4. Adminer answers on the host too, wherever it ended up.
code=$(curl -s -m 5 -o /dev/null -w '%{http_code}' "http://localhost:${adm_pub##*:}/")
[[ "$code" == "200" ]] || fail "adminer on http://localhost:${adm_pub##*:}/ returned $code, expected 200"
echo "✓ adminer reachable on http://localhost:${adm_pub##*:}/"

echo "PASS: case 05 solved"
