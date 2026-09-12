#!/usr/bin/env bash
# Prints the evidence a support engineer would ask for, labelled by source.
#
#   ./tools/evidence.sh            everything
#   ./tools/evidence.sh <section>  one of: containers executions paths config redis concurrency downstream
#
# Every block shows the command that produced it, so you can run it yourself
# and so you learn the command rather than this script. Read-only: nothing
# here changes the deployment.
set -uo pipefail
. "$(dirname "$0")/../lib/common.sh"

WANT=${1:-all}
show() { [ "$WANT" = all ] || [ "$WANT" = "$1" ]; }
cmd() { printf '\n\033[2m$ %s\033[0m\n' "$*"; }

if show containers; then
	step "containers  (source: Docker)"
	cmd "docker compose ps --format 'table {{.Name}}\t{{.Status}}'"
	docker compose ps --format 'table {{.Name}}\t{{.Status}}'
fi

if show executions; then
	step "executions  (source: Postgres, table execution_entity)"
	cmd "psql: last 12 executions with queue wait and run time"
	docker compose exec -T postgres psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c "
SELECT id, mode, status,
       to_char(\"createdAt\", 'HH24:MI:SS') AS created,
       ROUND(EXTRACT(EPOCH FROM (\"startedAt\" - \"createdAt\"))::numeric, 2) AS queue_wait_s,
       ROUND(EXTRACT(EPOCH FROM (\"stoppedAt\" - \"startedAt\"))::numeric, 2) AS run_s,
       \"retryOf\" AS retry_of
FROM execution_entity ORDER BY id DESC LIMIT 12;"
fi

if show paths; then
	step "which process ran what  (source: container logs)"
	cmd "docker compose logs n8n-main | grep 'Enqueued execution'"
	docker compose logs --no-log-prefix n8n-main 2>/dev/null | grep 'Enqueued execution' | tail -5
	cmd "docker compose logs n8n-worker | grep -E 'Worker (started|finished) execution|could not be decrypted'"
	docker compose logs n8n-worker 2>/dev/null | grep -E 'Worker (started|finished) execution|could not be decrypted' | tail -8
	cmd "docker compose logs n8n-main | grep -A1 OFFLOAD_MANUAL"
	docker compose logs --no-log-prefix n8n-main 2>/dev/null | grep -m1 'OFFLOAD_MANUAL' | cut -c1-160
fi

if show config; then
	step "effective settings inside each running container  (source: the container's environment)"
	info "keys are shown as a sha256 prefix: compare them without printing secrets"
	printf '  %-20s %-10s %-10s %-14s %-12s %s\n' container REDIS_DB PREFIX KEY_SHA256 CONC_LIMIT command
	for c in $(docker compose ps n8n-main n8n-worker --format '{{.Name}}'); do
		docker exec "$c" sh -c '
			printf "  %-20s %-10s %-10s %-14s %-12s %s\n" "$0" \
				"${QUEUE_BULL_REDIS_DB:-0}" "${QUEUE_BULL_PREFIX:-bull}" \
				"$(printf %s "$N8N_ENCRYPTION_KEY" | sha256sum | cut -c1-12)" \
				"${N8N_CONCURRENCY_PRODUCTION_LIMIT:-unset}" \
				"$(tr "\0" " " </proc/1/cmdline | sed "s#tini -- /docker-entrypoint.sh *##; s#^\$#start (image default)#")"' "${c#qmlab-}"
	done
	cmd "docker compose exec n8n-main printenv QUEUE_BULL_REDIS_DB   # and: --index 2 n8n-worker"
fi

if show redis; then
	step "redis  (source: redis-cli inside the redis container)"
	cmd "docker compose exec redis redis-cli ping"
	redis_q 0 ping
	cmd "docker compose exec redis redis-cli INFO keyspace"
	redis_q 0 INFO keyspace | tr -d '\r' | grep -v '^$'
	for db in $(redis_q 0 INFO keyspace | tr -d '\r' | sed -n 's/^db\([0-9]*\):.*/\1/p'); do
		cmd "docker compose exec redis redis-cli -n $db LLEN bull:jobs:wait   (and :active)"
		echo "  db$db  waiting=$(redis_q "$db" LLEN bull:jobs:wait)  active=$(redis_q "$db" LLEN bull:jobs:active)"
	done
	cmd "docker compose exec redis redis-cli CLIENT LIST   # who is blocked waiting for jobs, on which db"
	redis_q 0 CLIENT LIST | tr -d '\r' | grep 'cmd=brpoplpush' \
		| sed -n 's/.* addr=\([0-9.]*\):.* db=\([0-9]*\) .*/\1 \2/p' \
		| while read -r ip db; do
			who=$(docker ps --filter "network=qmlab_default" --format '{{.Names}}' | while read -r n; do
				[ "$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "$n")" = "$ip" ] && echo "${n#qmlab-}"; done)
			echo "  ${who:-$ip} is waiting for jobs on db$db"
		done
	cmd "docker compose exec redis redis-cli PUBSUB CHANNELS 'n8n*'   # pub/sub ignores the db number"
	redis_q 0 PUBSUB CHANNELS 'n8n*' | tr -d '\r'
fi

if show concurrency; then
	step "concurrency each worker actually uses  (source: worker startup log)"
	cmd "docker compose logs n8n-worker | grep 'Concurrency:'"
	effective_concurrency | sed 's/^/  /; s/ \([0-9]*\)$/  Concurrency: \1/'
fi

if show downstream; then
	step "fulfilment-api  (source: its own /stats endpoint)"
	cmd "curl -s $API_URL/stats"
	curl -s "$API_URL/stats" | sed 's/,"recent".*//; s/,/, /g'
	echo
	cmd "docker compose logs --tail 5 fulfilment-api"
	docker compose logs --no-log-prefix --tail 5 fulfilment-api
fi
