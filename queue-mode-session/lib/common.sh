# shellcheck shell=bash disable=SC2034  # variables here are used by the scripts that source this file
# Shared helpers for the queue-mode lab scripts. Sourced, never executed.
#
# Everything here talks to the running stack the same way you would by hand:
# curl against main's public port, psql inside the postgres container, and
# redis-cli inside the redis container. Nothing reads files you might have
# edited, so a check passes because the deployment works, not because a line
# looks right.

LAB_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$LAB_DIR" || exit 1

# Read, never exported: an exported WORKER_REPLICAS (or any other key) would
# override .env for every docker compose call this script makes, so an edit to
# .env made meanwhile would silently not apply. Compose reads .env itself.
# shellcheck disable=SC1091
. "$LAB_DIR/.env"
MAIN_URL="http://localhost:${MAIN_PORT:-5690}"
API_URL="http://localhost:${FULFILMENT_PORT:-5692}"
CONSOLE_URL="http://localhost:${CONSOLE_PORT:-5691}"
OWNER_EMAIL=${N8N_OWNER_EMAIL:-owner@example.com}
OWNER_PASSWORD=DockerLab2026
WORKFLOW_ID=qmLabOrderIntake

ok()   { printf '  \033[32m✓\033[0m %s\n' "$*"; }
bad()  { printf '  \033[31m✗\033[0m %s\n' "$*"; }
info() { printf '  · %s\n' "$*"; }
step() { printf '\n\033[1m%s\033[0m\n' "$*"; }

need() {
	command -v "$1" >/dev/null 2>&1 || { echo "This lab needs '$1' on your PATH." >&2; exit 1; }
}
need docker
need curl
docker info >/dev/null 2>&1 || { echo "Docker is not running. Start Docker Desktop (or the daemon) and retry." >&2; exit 1; }

psql_q() { # $1 = SQL, prints unaligned tuples
	docker compose exec -T postgres psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -tAc "$1" 2>/dev/null
}

redis_q() { # redis_q <db> <command...>
	local db=$1; shift
	docker compose exec -T redis redis-cli -n "$db" "$@" 2>/dev/null
}

max_execution_id() { psql_q 'SELECT COALESCE(MAX(id), 0) FROM execution_entity;'; }

wait_healthy() { # wait_healthy <service> [timeout_s]
	local svc=$1 limit=${2:-180} waited=0 states
	while :; do
		states=$(docker compose ps -a "$svc" --format '{{.State}}/{{.Health}}' 2>/dev/null)
		if [ -n "$states" ] && ! echo "$states" | grep -qv '^running/healthy$'; then
			return 0
		fi
		[ "$waited" -ge "$limit" ] && return 1
		sleep 3; waited=$((waited + 3))
	done
}

# Production path: exactly what the customer's shop does. POST to the webhook.
send_order() { # send_order <order-ref>  -> prints HTTP status
	curl -s -o /dev/null -w '%{http_code}' -X POST "$MAIN_URL/webhook/orders" \
		-H 'content-type: application/json' -d "{\"order\":\"$1\"}"
}

# Manual path: what clicking "Execute workflow" in the editor sends.
N8N_COOKIE_JAR=""
N8N_BROWSER_ID="qmlab-$$"
n8n_login() {
	N8N_COOKIE_JAR=$(mktemp)
	local code
	code=$(curl -s -o /dev/null -w '%{http_code}' -c "$N8N_COOKIE_JAR" \
		-H "browser-id: $N8N_BROWSER_ID" -H 'content-type: application/json' \
		-X POST "$MAIN_URL/rest/login" \
		-d "{\"emailOrLdapLoginId\":\"$OWNER_EMAIL\",\"password\":\"$OWNER_PASSWORD\"}")
	[ "$code" = "200" ]
}

manual_run() { # prints the execution ID main returns
	[ -n "$N8N_COOKIE_JAR" ] || n8n_login || { echo "login-failed"; return 1; }
	curl -s -b "$N8N_COOKIE_JAR" -H "browser-id: $N8N_BROWSER_ID" -H 'content-type: application/json' \
		-X POST "$MAIN_URL/rest/workflows/$WORKFLOW_ID/run" \
		-d '{"triggerToStartFrom":{"name":"Manual test"}}' \
		| sed -n 's/.*"executionId":"\([0-9]*\)".*/\1/p'
}

execution_status() { psql_q "SELECT status FROM execution_entity WHERE id = $1;"; }

wait_for_status() { # wait_for_status <id> <timeout_s> -> prints final status
	local id=$1 limit=$2 waited=0 s
	while :; do
		s=$(execution_status "$id")
		case "$s" in success|error|crashed|canceled) echo "$s"; return 0 ;; esac
		[ "$waited" -ge "$limit" ] && { echo "${s:-missing}"; return 1; }
		sleep 1; waited=$((waited + 1))
	done
}

worker_count() { docker compose ps n8n-worker --format '{{.Name}}' | wc -l | tr -d ' '; }

# Copy env/baseline/ back into place. Saves anything it overwrites to
# env/before-reset/ so a participant's edits are never silently lost.
restore_baseline_config() { # [quiet]
	mkdir -p env/before-reset
	local pair src dst
	for pair in "lab.env:.env" "main.env:env/main.env" "worker.env:env/worker.env"; do
		src="env/baseline/${pair%%:*}"; dst="${pair#*:}"
		if ! cmp -s "$src" "$dst"; then
			cp "$dst" "env/before-reset/${pair%%:*}" 2>/dev/null || true
			cp "$src" "$dst"
			[ -z "${1:-}" ] && ok "restored $dst (your version is in env/before-reset/${pair%%:*})"
		else
			[ -z "${1:-}" ] && ok "$dst already matches the baseline"
		fi
	done
	. "$LAB_DIR/.env"
}

# Recreate whatever the current config says, with an empty queue.
apply_config() {
	docker compose up -d --force-recreate --remove-orphans redis >/dev/null 2>&1
	docker compose up -d --remove-orphans >/dev/null 2>&1
	docker compose restart n8n-main n8n-worker >/dev/null 2>&1
	wait_healthy n8n-main 240 && wait_healthy n8n-worker 180
}

# The concurrency each worker says it is using, from its own startup log.
effective_concurrency() {
	docker compose logs n8n-worker 2>/dev/null \
		| sed -n 's/^\(n8n-worker-[0-9]*\).*\* Concurrency: \([0-9]*\).*/\1 \2/p' \
		| awk '{last[$1]=$2} END {for (w in last) print w, last[w]}' | sort
}

STATE_DIR="$LAB_DIR/incidents/.state"

# What "Retry" in the editor's Executions list sends. loadWorkflow=false re-runs
# with the workflow as it was when the execution started.
retry_execution() { # prints the new execution's status
	[ -n "$N8N_COOKIE_JAR" ] || n8n_login || return 1
	curl -s -b "$N8N_COOKIE_JAR" -H "browser-id: $N8N_BROWSER_ID" -H 'content-type: application/json' \
		-X POST "$MAIN_URL/rest/executions/$1/retry" -d '{"loadWorkflow":false}' \
		| sed -n 's/.*"status":"\([a-z]*\)".*/\1/p' | head -1
}
