#!/usr/bin/env bash
# Rehearses the whole workshop from a clean start, asserts every claim the
# lesson page makes, and records the evidence the page shows as "RECORDED".
#
#   ./tools/rehearse.sh
#
# For whoever maintains the lab, not for participants. It deletes the lab's
# data (./reset.sh --full) and takes about ten minutes. Needs python3 on the
# host to write console/public/data/evidence.json.
#
# Exit status is the number of failed assertions. A run log goes to
# tools/last-rehearsal.log.
set -uo pipefail
. "$(dirname "$0")/../lib/common.sh"
need python3

OUT=$(mktemp -d)
LOG="$LAB_DIR/tools/last-rehearsal.log"
: >"$LOG"
FAILED=0
strip() { sed -E 's/\x1b\[[0-9;]*m//g'; }
say() { echo "$*" | tee -a "$LOG"; }
assert() { # assert <description> <command...>
	local what=$1; shift
	if "$@" >>"$LOG" 2>&1; then say "  ✓ $what"; else say "  ✗ $what"; FAILED=$((FAILED + 1)); fi
}
# cap <id> <title> <display command> -- <command to run...>
cap() {
	local id=$1 title=$2 shown=$3; shift 4
	"$@" 2>&1 | strip >"$OUT/$id.out"
	printf '%s\n%s\n' "$title" "$shown" >"$OUT/$id.meta"
}
result_of() { grep '^RESULT' | tail -1; }
metric() { # metric <name> <RESULT line> <concurrency>
	echo "$2 concurrency=$3" >"$OUT/metric.$1"
}
status_is() { [ "$(execution_status "$1")" = "$2" ]; }
not() { ! "$@"; }

say "Rehearsal started $(date -u +%FT%TZ)"

# ---------------------------------------------------------------------------
say ""; say "== Baseline from a clean start"
./reset.sh --full >/dev/null 2>&1
cap baseline.verify "./verify.sh on a fresh ./setup.sh" "./verify.sh" -- ./verify.sh
assert "baseline verify passes" grep -q '^PASS' "$OUT/baseline.verify.out"

# ---------------------------------------------------------------------------
say ""; say "== Lesson 0"
send_order TRACE-1 >/dev/null; sleep 3
n8n_login; man=$(manual_run); sleep 3
cap trace.paths "Enqueued by main, started by a worker" "./tools/evidence.sh paths" -- ./tools/evidence.sh paths
assert "manual execution $man is not in any worker log" not grep -q "Worker started execution $man " "$OUT/trace.paths.out"
assert "main logs the OFFLOAD_MANUAL deprecation" grep -q OFFLOAD_MANUAL "$OUT/trace.paths.out"
cap trace.config "Effective settings in each running container" "./tools/evidence.sh config" -- ./tools/evidence.sh config
cap trace.load "Baseline load: 2 workers × concurrency 5, API capacity 10" "./tools/load-test.sh 100 25" -- ./tools/load-test.sh 100 25
base=$(result_of <"$OUT/trace.load.out"); metric baseline "$base" 5
assert "baseline load: 100/100 succeed" grep -q ' success=100 ' <<<"$base"
assert "baseline load: no 429s" grep -q ' api_429=0 ' <<<"$base"

# ---------------------------------------------------------------------------
say ""; say "== Incident 1"
I1=incidents/01-it-works-when-i-click-execute
$I1/setup.sh >/dev/null 2>&1
start=$(cat "$STATE_DIR/01.start")
cap inc1.ps "Every container running and healthy" "docker compose ps --format 'table {{.Name}}\t{{.Status}}'" -- docker compose ps --format 'table {{.Name}}\t{{.Status}}'
assert "incident 1: no container is unhealthy" not grep -qE 'unhealthy|Restarting|Exited' "$OUT/inc1.ps.out"
cap inc1.executions "Three manual tests succeeded and four shop orders failed" "./tools/evidence.sh executions" -- ./tools/evidence.sh executions
assert "incident 1: manual runs succeeded" test "$(psql_q "SELECT COUNT(*) FROM execution_entity WHERE id > $start AND mode='manual' AND status='success'")" = 3
assert "incident 1: shop orders failed" test "$(psql_q "SELECT COUNT(*) FROM execution_entity WHERE id > $start AND mode='webhook' AND status='error'")" = 4
cap inc1.paths "What the worker says about a shop order" "docker compose logs n8n-worker | grep -A1 'could not be decrypted'" -- \
	sh -c "docker compose logs n8n-worker | grep -E -A1 'Worker started execution|could not be decrypted' | grep -v -- '--' | head -6"
assert "incident 1: worker logs the decryption error" grep -q 'could not be decrypted' "$OUT/inc1.paths.out"
cap inc1.config "Key hashes differ between main and workers" "./tools/evidence.sh config" -- ./tools/evidence.sh config
assert "incident 1: verify fails while broken" not $I1/verify.sh

say "  -- wrong fix: copy the workers' key into main"
sed -i.bak "s/^N8N_ENCRYPTION_KEY=.*/$(grep '^N8N_ENCRYPTION_KEY=' env/worker.env)/" env/main.env && rm -f env/main.env.bak
docker compose up -d n8n-main >/dev/null 2>&1; sleep 20
cap inc1.wrongfix "Main after being given the workers' key" "docker compose ps n8n-main; docker compose logs n8n-main | grep -m1 Mismatching" -- \
	sh -c "docker compose ps n8n-main --format '{{.Name}}  {{.Status}}'; docker compose logs --no-log-prefix n8n-main | grep -m1 Mismatching"
assert "incident 1 wrong fix: main refuses to start (mismatching keys)" grep -q 'Mismatching encryption keys' "$OUT/inc1.wrongfix.out"
assert "incident 1 wrong fix: main is not healthy" not wait_healthy n8n-main 10

say "  -- right fix: workers get main's original key"
cp env/baseline/main.env env/main.env; cp env/baseline/worker.env env/worker.env
docker compose up -d n8n-main n8n-worker >/dev/null 2>&1; wait_healthy n8n-main 240; wait_healthy n8n-worker 180
cap inc1.verify "Retest on the production path" "./incidents/01-it-works-when-i-click-execute/verify.sh" -- $I1/verify.sh
assert "incident 1: verify passes after the fix" grep -q '^PASS' "$OUT/inc1.verify.out"
n8n_login
first_failed=$(psql_q "SELECT MIN(id) FROM execution_entity WHERE id > $start AND mode='webhook' AND status='error'")
assert "incident 1: a failed shop order retries successfully after the fix" test "$(retry_execution "$first_failed")" = success

# ---------------------------------------------------------------------------
say ""; say "== Incident 2"
I2=incidents/02-redis-said-pong
$I2/setup.sh >/dev/null 2>&1
start=$(cat "$STATE_DIR/02.start")
cap inc2.executions "The five orders stay new and never start" "./tools/evidence.sh executions" -- ./tools/evidence.sh executions
assert "incident 2: the five orders are still new after setup" test "$(psql_q "SELECT COUNT(*) FROM execution_entity WHERE id > $start AND status='new'")" = 5
cap inc2.mainlog "Main enqueued all five, with job numbers starting again at 1" "docker compose logs n8n-main | grep 'Enqueued execution'" -- \
	sh -c "docker compose logs --no-log-prefix n8n-main | grep 'Enqueued execution' | tail -5"
assert "incident 2: job numbering restarted at 1" grep -q '(job 1)' "$OUT/inc2.mainlog.out"
cap inc2.redis "Redis answers PONG, the jobs sit in db1, and the workers wait on db0" "./tools/evidence.sh redis" -- ./tools/evidence.sh redis
assert "incident 2: redis answers PONG" grep -q PONG "$OUT/inc2.redis.out"
assert "incident 2: 5 jobs waiting in db1" grep -q 'db1  waiting=5' "$OUT/inc2.redis.out"
assert "incident 2: both workers wait on db0" test "$(grep -c 'n8n-worker-[0-9]* is waiting for jobs on db0' "$OUT/inc2.redis.out")" = 2
assert "incident 2: no consumer waits on db1" not grep -q 'is waiting for jobs on db1' "$OUT/inc2.redis.out"
assert "incident 2: n8n pub/sub channels exist regardless" grep -q 'n8n:n8n.commands' "$OUT/inc2.redis.out"
cap inc2.config "Main and workers disagree about QUEUE_BULL_REDIS_DB" "./tools/evidence.sh config" -- ./tools/evidence.sh config
assert "incident 2: all containers healthy" not sh -c "docker compose ps | grep -qE 'unhealthy|Restarting'"
assert "incident 2: verify fails while broken" not $I2/verify.sh

say "  -- recovery A: workers move to db1"
sed -i.bak 's/^QUEUE_BULL_REDIS_DB=.*/QUEUE_BULL_REDIS_DB=1/' env/worker.env && rm -f env/worker.env.bak
docker compose up -d n8n-worker >/dev/null 2>&1; wait_healthy n8n-worker 180; sleep 5
cap inc2.fixA.executions "Recovery A: the five queued orders run once the workers move" "./tools/evidence.sh executions" -- ./tools/evidence.sh executions
assert "recovery A: all five incident orders succeeded" test "$(psql_q "SELECT COUNT(*) FROM execution_entity WHERE id > $start AND id <= $(cat "$STATE_DIR/02.end") AND status='success'")" = 5
assert "recovery A: verify passes" $I2/verify.sh

say "  -- recovery B: main moves back to db0"
$I2/setup.sh >/dev/null 2>&1
start=$(cat "$STATE_DIR/02.start")
cp env/baseline/main.env env/main.env
docker compose up -d n8n-main >/dev/null 2>&1; wait_healthy n8n-main 240; sleep 3
cap inc2.fixB.mainlog "Recovery B: main's startup queue recovery" "docker compose logs n8n-main | grep -iE 'crashed|queue recovery'" -- \
	sh -c "docker compose logs --no-log-prefix --since 5m n8n-main | grep -iE 'crashed|queue recovery'"
assert "recovery B: main marks the stranded executions crashed" test "$(psql_q "SELECT COUNT(*) FROM execution_entity WHERE id > $start AND status='crashed'")" = 5
assert "recovery B: the jobs are still in db1" test "$(redis_q 1 LLEN bull:jobs:wait | tr -d '\r')" = 5
assert "recovery B: verify fails before the retries" not $I2/verify.sh
n8n_login
for id in $(psql_q "SELECT id FROM execution_entity WHERE id > $start AND id <= $(cat "$STATE_DIR/02.end") AND status='crashed' ORDER BY id"); do
	retry_execution "$id" >/dev/null
done
sleep 2
cap inc2.fixB.executions "Recovery B: crashed orders retried with their original payload" "./tools/evidence.sh executions" -- ./tools/evidence.sh executions
assert "recovery B: fulfilment-api received the original order references" sh -c "docker compose logs fulfilment-api --since 2m | grep -q 'order=SHOP-4401 mode=production'"
assert "recovery B: verify passes after retrying" $I2/verify.sh

# ---------------------------------------------------------------------------
say ""; say "== Incident 3"
I3=incidents/03-we-added-workers
cap inc3.setup "The customer's load test" "./incidents/03-we-added-workers/setup.sh" -- $I3/setup.sh
inc=$(result_of <"$OUT/inc3.setup.out")
cap inc3.concurrency "What each worker says at startup" "docker compose logs n8n-worker | grep 'Concurrency:'" -- ./tools/evidence.sh concurrency
metric incident "$inc" "$(effective_concurrency | awk '{print $2}' | sort -u | head -1)"
assert "incident 3: 5 workers" test "$(worker_count)" = 5
assert "incident 3: every worker reports Concurrency: 20" test "$(effective_concurrency | awk '{print $2}' | sort -u)" = 20
assert "incident 3: the worker command says 200" sh -c "docker compose exec -T n8n-worker cat /proc/1/cmdline | tr '\0' ' ' | grep -q -- '--concurrency=200'"
assert "incident 3: fewer than 100 orders succeed" not grep -q ' success=100 ' <<<"$inc"
assert "incident 3: the API refused requests" not grep -q ' api_429=0 ' <<<"$inc"
cap inc3.config "Worker command line and environment side by side" "./tools/evidence.sh config" -- ./tools/evidence.sh config
cap inc3.downstream "The fulfilment API's counters" "./tools/evidence.sh downstream" -- ./tools/evidence.sh downstream
mem=$(docker stats --no-stream --format '{{.Name}} {{.MemUsage}}' | grep '^qmlab-' | awk '{v=$2; if (v ~ /GiB/) {sub(/GiB/,"",v); v*=1024} else sub(/MiB/,"",v); s+=v} END {printf "%.0f", s}')
say "  · memory in use with 5 workers: ${mem} MiB"
assert "incident 3: verify fails while broken" not sh -c "$I3/verify.sh >/dev/null 2>&1"

say "  -- remedy: keep 5 workers, N8N_CONCURRENCY_PRODUCTION_LIMIT=2"
sed -i.bak 's/^N8N_CONCURRENCY_PRODUCTION_LIMIT=.*/N8N_CONCURRENCY_PRODUCTION_LIMIT=2/' env/worker.env && rm -f env/worker.env.bak
docker compose up -d n8n-worker >/dev/null 2>&1; wait_healthy n8n-worker 180
cap inc3.verify "The fix, measured with the same load" "./incidents/03-we-added-workers/verify.sh" -- $I3/verify.sh
metric remedy "$(result_of <"$OUT/inc3.verify.out")" 2
assert "incident 3 remedy: verify passes" grep -q '^PASS' "$OUT/inc3.verify.out"
assert "incident 3 remedy: still 5 workers" test "$(worker_count)" = 5
assert "incident 3 remedy: every worker reports Concurrency: 2" test "$(effective_concurrency | awk '{print $2}' | sort -u)" = 2
assert "incident 3 remedy: workers warn about concurrency below 5" sh -c "docker compose logs n8n-worker | grep -q 'less than 5'"

# ---------------------------------------------------------------------------
say ""; say "== Back to baseline"
cap final.reset "./reset.sh" "./reset.sh" -- ./reset.sh
assert "reset ends with a passing verify" grep -q '^PASS' "$OUT/final.reset.out"
assert "reset restored 2 workers" test "$(worker_count)" = 2

# ---------------------------------------------------------------------------
python3 - "$OUT" "$LAB_DIR/console/public/data/evidence.json" "$mem" <<'PY'
import json, os, sys, datetime, glob
out, dest, mem = sys.argv[1], sys.argv[2], sys.argv[3]
items = {}
for meta in sorted(glob.glob(os.path.join(out, '*.meta'))):
    key = os.path.basename(meta)[:-5]
    title, command = open(meta).read().split('\n')[:2]
    output = open(os.path.join(out, key + '.out')).read().rstrip()
    items[key] = {'title': title, 'command': command, 'output': output}
metrics = {}
for f in glob.glob(os.path.join(out, 'metric.*')):
    kv = dict(p.split('=', 1) for p in open(f).read().split()[1:] if '=' in p)
    metrics[f.rsplit('.', 1)[1]] = kv
os.makedirs(os.path.dirname(dest), exist_ok=True)
json.dump({
    'captured_at': datetime.datetime.now(datetime.timezone.utc).isoformat(timespec='seconds'),
    'n8n_version': '2.33.0',
    'memory_mib_5_workers': mem,
    'items': items,
    'metrics': metrics,
}, open(dest, 'w'), indent=1)
print(f'wrote {len(items)} evidence items and {len(metrics)} metric sets to {dest}')
PY

say ""
if [ "$FAILED" -eq 0 ]; then say "REHEARSAL PASS: every assertion held. Evidence written to console/public/data/evidence.json"
else say "REHEARSAL FAIL: $FAILED assertion(s) failed. See $LOG"; fi
rm -rf "$OUT"
exit "$FAILED"
