#!/usr/bin/env bash
# Case 02 check. It asks n8n for the credential the same way the editor does and
# looks at what comes back: not at what you edited. Any fix that really works
# will pass.
set -uo pipefail
cd "$(dirname "$0")"

PORT=5602
JAR=$(mktemp -t docklab-02-cookie)
trap 'rm -f "$JAR"' EXIT
fail() { echo "✗ $1"; echo "FAIL: case 02 not solved"; exit 1; }

# 1. n8n has to be up and ready. Readiness, never /healthz. /healthz returns
#    200 by design even with no database at all.
for _ in $(seq 1 60); do
  code=$(curl -s -o /dev/null -w '%{http_code}' "http://localhost:$PORT/healthz/readiness")
  [[ "$code" == "200" ]] && break
  sleep 2
done
[[ "$code" == "200" ]] || fail "readiness on port $PORT returned $code, expected 200, start with: docker compose ps"
echo "✓ n8n ready on http://localhost:$PORT/healthz/readiness"

# 2. Log in as the instance owner, exactly as the browser does.
code=$(curl -s -c "$JAR" -o /dev/null -w '%{http_code}' -X POST "http://localhost:$PORT/rest/login" \
  -H 'Content-Type: application/json' \
  -d '{"emailOrLdapLoginId":"owner@example.com","password":"DockerLab2026"}')
[[ "$code" == "200" ]] && grep -q n8n-auth "$JAR" || fail "login as owner@example.com returned $code"
echo "✓ logged in as owner@example.com"

# 3. Ask for the credential WITH its data: that is what the editor does when
#    you open one.
body=$(curl -s -b "$JAR" "http://localhost:$PORT/rest/credentials?includeData=true")
grep -q 'DockLabCred00001' <<<"$body" || fail "the customer's credential is not in this instance at all"
grep -q '"data":{}' <<<"$body" && fail "the credential came back with an empty data object, n8n still cannot read it"
grep -q '"name":"X-Api-Key"' <<<"$body" || fail "unexpected credential payload: $body"
echo "✓ the customer's credential decrypts, data.name is X-Api-Key"

echo "PASS: case 02 solved. Open http://localhost:$PORT"
