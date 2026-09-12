#!/usr/bin/env bash
# Sends a burst of production orders and measures what actually got done.
#
#   ./tools/load-test.sh [orders=100] [parallel=25]
#
# It resets the fulfilment-api counters, fires the orders at the webhook, waits
# for every resulting execution to finish, then reports numbers from Postgres
# (what n8n recorded) and from the fulfilment API (what it accepted or refused).
# Worker count and concurrency are printed for context, not as a result.
set -uo pipefail
. "$(dirname "$0")/../lib/common.sh"

ORDERS=${1:-100}
PARALLEL=${2:-25}
TIMEOUT=${LOAD_TIMEOUT:-300}
RUN="L$(date +%H%M%S)"

before=$(max_execution_id)
curl -s -X POST "$API_URL/stats/reset" >/dev/null || { echo "fulfilment-api is not answering on $API_URL"; exit 1; }

step "Load test $RUN: $ORDERS orders, $PARALLEL at a time, $(worker_count) worker container(s)"
t0=$(date +%s)
codes=$(seq 1 "$ORDERS" | xargs -P "$PARALLEL" -I{} curl -s -o /dev/null -w '%{http_code}\n' \
	-X POST "$MAIN_URL/webhook/orders" -H 'content-type: application/json' \
	-d "{\"order\":\"$RUN-{}\"}")
accepted_http=$(echo "$codes" | grep -c '^200$')
info "webhook answered 200 for $accepted_http/$ORDERS requests in $(( $(date +%s) - t0 ))s"

waited=0
while :; do
	pending=$(psql_q "SELECT COUNT(*) FROM execution_entity WHERE id > $before AND status IN ('new','running','waiting');")
	total=$(psql_q "SELECT COUNT(*) FROM execution_entity WHERE id > $before;")
	[ "$pending" = "0" ] && [ "$total" -ge "$accepted_http" ] && break
	[ "$waited" -ge "$TIMEOUT" ] && { bad "gave up after ${TIMEOUT}s with $pending still pending"; break; }
	sleep 2; waited=$((waited + 2))
done

# One query, so every number describes the same set of executions.
read -r success failed crashed pending wall rate wait_p50 wait_p95 dur_p50 dur_p95 <<<"$(psql_q "
WITH r AS (
  SELECT status, \"createdAt\" c, \"startedAt\" s, \"stoppedAt\" e
  FROM execution_entity WHERE id > $before AND mode = 'webhook'
)
SELECT
  COUNT(*) FILTER (WHERE status = 'success'),
  COUNT(*) FILTER (WHERE status = 'error'),
  COUNT(*) FILTER (WHERE status = 'crashed'),
  COUNT(*) FILTER (WHERE status IN ('new','running','waiting')),
  ROUND(EXTRACT(EPOCH FROM (MAX(e) - MIN(c)))::numeric, 1),
  ROUND((COUNT(*) FILTER (WHERE status = 'success') / NULLIF(EXTRACT(EPOCH FROM (MAX(e) - MIN(c))), 0))::numeric, 1),
  ROUND((PERCENTILE_CONT(0.5)  WITHIN GROUP (ORDER BY EXTRACT(EPOCH FROM (s - c))))::numeric, 2),
  ROUND((PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY EXTRACT(EPOCH FROM (s - c))))::numeric, 2),
  ROUND((PERCENTILE_CONT(0.5)  WITHIN GROUP (ORDER BY EXTRACT(EPOCH FROM (e - s))))::numeric, 2),
  ROUND((PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY EXTRACT(EPOCH FROM (e - s))))::numeric, 2)
FROM r;" | tr '|' ' ')"

api=$(curl -s "$API_URL/stats")
jnum() { echo "$api" | sed -n "s/.*\"$1\":\([0-9]*\).*/\1/p"; }

step "Result ($RUN)"
printf '  %-38s %s\n' \
	"executions succeeded"                "$success / $ORDERS" \
	"executions failed (error)"           "$failed" \
	"executions crashed / still pending"  "$crashed / $pending" \
	"first enqueue to last finish"        "${wall}s" \
	"successful orders per second"        "$rate" \
	"queue wait p50 / p95"                "${wait_p50}s / ${wait_p95}s" \
	"execution duration p50 / p95"        "${dur_p50}s / ${dur_p95}s" \
	"fulfilment-api accepted (200)"       "$(jnum accepted)" \
	"fulfilment-api refused (429)"        "$(jnum rejected_429)" \
	"fulfilment-api peak in flight"       "$(jnum peak_in_flight) (capacity $(jnum capacity))"

# Machine-readable line for tools/rehearse.sh and your own notes.
echo "RESULT run=$RUN orders=$ORDERS workers=$(worker_count) success=$success error=$failed crashed=$crashed pending=$pending wall_s=$wall success_per_s=$rate wait_p50=$wait_p50 wait_p95=$wait_p95 dur_p50=$dur_p50 dur_p95=$dur_p95 api_200=$(jnum accepted) api_429=$(jnum rejected_429) api_peak=$(jnum peak_in_flight)"
