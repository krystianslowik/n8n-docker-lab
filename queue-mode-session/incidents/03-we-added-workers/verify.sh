#!/usr/bin/env bash
# Incident 03 check. Runs the customer's load test and judges the result on
# useful work: orders completed and pressure on the fulfilment API. Worker count
# and an empty queue are reported, but they are not the pass condition.
set -uo pipefail
. "$(dirname "$0")/../../lib/common.sh"
failures=0
fail() { bad "$1"; failures=$((failures + 1)); }

step "Incident 03: effective capacity (from each worker's own startup log)"
total=0
while read -r w c; do
	[ -z "$w" ] && continue
	info "$w says Concurrency: $c"; total=$((total + c))
done <<<"$(effective_concurrency)"
cap=$(curl -s "$API_URL/stats" | sed -n 's/.*"capacity":\([0-9]*\).*/\1/p')
info "total execution slots: $total, fulfilment-api capacity: $cap"

result=$("$LAB_DIR/tools/load-test.sh" 100 25 | tee /dev/stderr | grep '^RESULT')
get() { echo "$result" | sed -n "s/.* $1=\([^ ]*\).*/\1/p"; }

step "Incident 03: judged on useful work"
[ "$(get success)" = "100" ] && ok "100/100 orders completed" || fail "$(get success)/100 orders completed"
refused=$(get api_429)
[ "${refused:-999}" -le 5 ] && ok "fulfilment-api refused $refused requests (limit for a pass: 5)" \
	|| fail "fulfilment-api refused $refused requests (limit for a pass: 5). Each retry is another request it has to refuse."
rate=$(get success_per_s)
info "successful orders per second: $rate (the API tops out near $(( cap * 1000 / ${FULFILMENT_LATENCY_MS:-300} ))/s)"

echo
[ "$failures" -eq 0 ] && { echo "PASS: incident 03 solved. All 100 orders completed within what the fulfilment API can take."; exit 0; }
echo "FAIL: incident 03 not solved yet."; exit 1
