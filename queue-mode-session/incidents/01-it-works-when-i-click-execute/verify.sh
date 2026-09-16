#!/usr/bin/env bash
# Incident 01 check. It sends new work down both paths and looks at outcomes.
# It does not care which file you edited, only whether production orders get
# processed again without breaking the manual path.
set -uo pipefail
. "$(dirname "$0")/../../lib/common.sh"
failures=0
fail() { bad "$1"; failures=$((failures + 1)); }

step "Incident 01: is the production path fixed?"
states=$(docker compose ps -a n8n-worker --format '{{.State}}/{{.Health}}' | sort -u | paste -sd' ' -)
[ "$states" = "running/healthy" ] && ok "every worker is running/healthy" || fail "workers: ${states:-none}"

before=$(max_execution_id)
send_order "VERIFY-01-$(date +%s)" >/dev/null
prod_id=""
for _ in $(seq 1 15); do
	prod_id=$(psql_q "SELECT MIN(id) FROM execution_entity WHERE id > $before AND mode = 'webhook';")
	[ -n "$prod_id" ] && break; sleep 1
done
if [ -n "$prod_id" ]; then
	status=$(wait_for_status "$prod_id" 40)
	[ "$status" = "success" ] && ok "new production order: execution $prod_id $status" \
		|| fail "new production order: execution $prod_id is '$status'"
else
	fail "the webhook call did not create an execution"
fi

n8n_login || fail "owner login failed"
man_id=$(manual_run)
status=$(wait_for_status "${man_id:-0}" 40)
[ "$status" = "success" ] && ok "manual test still works: execution $man_id $status" \
	|| fail "manual test run is '$status'. Did the fix move the problem to main?"

echo
[ "$failures" -eq 0 ] && { echo "PASS: incident 01 solved. The retest used a production webhook, the path that failed."; exit 0; }
echo "FAIL: incident 01 not solved yet."; exit 1
