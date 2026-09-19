#!/usr/bin/env bash
# Incident 02 check. New work has to flow again, and the five orders the shop
# sent during the incident have to end up processed: either the queue delivered
# them after your fix, or you found them and retried them.
set -uo pipefail
. "$(dirname "$0")/../../lib/common.sh"
failures=0
fail() { bad "$1"; failures=$((failures + 1)); }

step "Incident 02: does queued work reach a worker?"
before=$(max_execution_id)
send_order "VERIFY-02-$(date +%s)" >/dev/null
prod_id=""
for _ in $(seq 1 15); do
	prod_id=$(psql_q "SELECT MIN(id) FROM execution_entity WHERE id > $before AND mode = 'webhook';")
	[ -n "$prod_id" ] && break; sleep 1
done
if [ -n "$prod_id" ]; then
	status=$(wait_for_status "$prod_id" 40)
	[ "$status" = "success" ] && ok "new production order: execution $prod_id $status" \
		|| fail "new production order: execution $prod_id is '$status' after 40s"
else
	fail "the webhook call did not create an execution"
fi

step "Incident 02: what happened to the five orders from the incident?"
start=$(cat "$STATE_DIR/02.start" 2>/dev/null); end=$(cat "$STATE_DIR/02.end" 2>/dev/null)
if [ -z "$start" ] || [ -z "$end" ]; then
	fail "no record of the incident's orders. Run ./setup.sh in this directory first."
else
	while IFS='|' read -r id status retried; do
		[ -z "$id" ] && continue
		if [ "$status" = "success" ]; then
			ok "execution $id: success"
		elif [ -n "$retried" ]; then
			ok "execution $id: $status, retried successfully as execution $retried"
		else
			fail "execution $id: $status, and not successfully retried"
		fi
	done <<<"$(psql_q "SELECT id, status, COALESCE(\"retrySuccessId\", '') FROM execution_entity WHERE id > $start AND id <= $end AND mode = 'webhook' ORDER BY id;")"
fi

echo
[ "$failures" -eq 0 ] && { echo "PASS: incident 02 solved, and no customer order was lost."; exit 0; }
echo "FAIL: incident 02 not solved yet."; exit 1
