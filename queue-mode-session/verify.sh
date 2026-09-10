#!/usr/bin/env bash
# Baseline check: is this a working queue-mode deployment, end to end?
#
#   ./verify.sh
#
# Green containers are step one, not the answer. This sends one production
# order and one manual test run, then checks which process ran each and that
# the fulfilment API actually received both.
set -uo pipefail
. "$(dirname "$0")/lib/common.sh"

failures=0
fail() { bad "$1"; failures=$((failures + 1)); }

step "Containers (what docker compose ps can tell you)"
for svc in postgres redis fulfilment-api n8n-main n8n-worker console; do
	states=$(docker compose ps -a "$svc" --format '{{.State}}/{{.Health}}' | sort | uniq -c | tr -s ' ' | sed 's/^ //')
	if [ -z "$states" ]; then fail "$svc: no container"; continue; fi
	case "$svc" in
		console) echo "$states" | grep -q 'running' && ok "$svc: $states" || fail "$svc: $states" ;;
		*) echo "$states" | grep -vq 'running/healthy' && fail "$svc: $states" || ok "$svc: $states" ;;
	esac
done

step "Production path: POST /webhook/orders"
before=$(max_execution_id)
code=$(send_order "VERIFY-$(date +%s)")
[ "$code" = "200" ] && ok "webhook answered 200" || fail "webhook answered $code"
prod_id=""
for _ in $(seq 1 15); do
	prod_id=$(psql_q "SELECT MIN(id) FROM execution_entity WHERE id > $before AND mode = 'webhook';")
	[ -n "$prod_id" ] && break; sleep 1
done
if [ -z "$prod_id" ]; then
	fail "no execution record appeared for the webhook call"
else
	status=$(wait_for_status "$prod_id" 30)
	[ "$status" = "success" ] && ok "execution $prod_id finished: $status" \
		|| fail "execution $prod_id is '$status' (expected success)"
	# Captured first: `logs | grep -q` under pipefail fails whenever grep exits
	# before docker has finished writing.
	worker_logs=$(docker compose logs n8n-worker --since 5m 2>/dev/null)
	if grep -q "Worker started execution $prod_id " <<<"$worker_logs"; then
		ok "a worker logged 'Worker started execution $prod_id', so the queue delivered it"
	else
		fail "no worker logged execution $prod_id"
	fi
fi

step "Manual path: what clicking Execute workflow sends"
if n8n_login; then
	man_id=$(manual_run)
	if [ -z "$man_id" ]; then
		fail "main did not return an execution ID for the manual run"
	else
		status=$(wait_for_status "$man_id" 30)
		[ "$status" = "success" ] && ok "manual execution $man_id finished: $status" \
			|| fail "manual execution $man_id is '$status' (expected success)"
		worker_logs=$(docker compose logs n8n-worker --since 5m 2>/dev/null)
		if grep -q "Worker started execution $man_id " <<<"$worker_logs"; then
			info "a worker ran manual execution $man_id (manual offloading is on)"
		else
			info "no worker logged execution $man_id: main ran it itself (manual offloading is off)"
		fi
	fi
else
	fail "owner login failed ($OWNER_EMAIL)"
fi

step "Downstream: did fulfilment-api receive the work?"
api=$(curl -s "$API_URL/stats")
grep -q '"mode":"production"' <<<"$api" && ok "fulfilment-api received a production request" \
	|| fail "fulfilment-api has no production request in its recent log"
grep -q '"mode":"test"' <<<"$api" && ok "fulfilment-api received a manual (test) request" \
	|| fail "fulfilment-api has no manual request in its recent log"

echo
if [ "$failures" -eq 0 ]; then
	echo "PASS: queue-mode baseline works end to end."
	echo "      n8n editor   $MAIN_URL  ($OWNER_EMAIL / $OWNER_PASSWORD)"
	echo "      console      $CONSOLE_URL"
	exit 0
fi
echo "FAIL: $failures check(s) failed. ./reset.sh restores the known-good configuration."
exit 1
