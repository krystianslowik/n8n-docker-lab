#!/usr/bin/env bash
# Puts the lab back to the known-good baseline.
#
#   ./reset.sh          restore configuration, empty the Redis queue, keep Postgres
#   ./reset.sh --full   delete everything (all three volumes) and run ./setup.sh
#
# What the default reset restores:
#   configuration  .env, env/main.env, env/worker.env copied from env/baseline/
#                  (your versions are saved to env/before-reset/ first)
#   Redis          recreated. It has no persistence, so every queued or stranded
#                  job is gone.
#   Postgres       untouched. Workflow, credential and execution history stay, so
#                  you can still look at what happened during an incident.
#
# It does not touch compose.yaml. If you edited that, `git diff compose.yaml`
# shows what you changed and `git checkout -- compose.yaml` undoes it.
set -uo pipefail
. "$(dirname "$0")/lib/common.sh"

if [ "${1:-}" = "--full" ]; then
	step "Full reset: restoring baseline configuration"
	restore_baseline_config
	step "Full reset: removing the qmlab containers, network and volumes"
	docker compose down -v --remove-orphans 2>&1 | grep -E 'Removed' | sed 's/^/  /'
	rm -rf "$STATE_DIR"
	exec "$LAB_DIR/setup.sh"
fi

step "Restoring baseline configuration"
restore_baseline_config

step "Recreating services (Redis first, so the queue starts empty)"
apply_config || { bad "services did not become healthy. Try ./reset.sh --full"; exit 1; }
curl -s -X POST "$API_URL/stats/reset" >/dev/null
rm -rf "$STATE_DIR"
ok "n8n-main and $(worker_count) worker(s) healthy, Redis queue empty, fulfilment-api counters cleared"

echo
exec "$LAB_DIR/verify.sh"
