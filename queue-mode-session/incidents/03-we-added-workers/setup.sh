#!/usr/bin/env bash
# Incident 03 setup. Prepares the customer's environment on top of a clean
# baseline, then replays their Black Friday rehearsal. Reading this file gives
# the answer away.
set -uo pipefail
. "$(dirname "$0")/../../lib/common.sh"
INC=03

step "Incident $INC: restoring the baseline first"
restore_baseline_config quiet

# Two changes on the same day. They scaled the workers and raised the flag.
sed -i.bak 's/^WORKER_REPLICAS=.*/WORKER_REPLICAS=5/; s/^WORKER_CONCURRENCY_FLAG=.*/WORKER_CONCURRENCY_FLAG=200/' .env && rm -f .env.bak
# And during the rebuild someone copied a line over from an old main config.
cat >> env/worker.env <<'ENV'

# Copied over from the old main.env during the worker rebuild.
N8N_CONCURRENCY_PRODUCTION_LIMIT=20
ENV

. "$LAB_DIR/.env"
apply_config || { bad "the stack did not come up healthy, try ./reset.sh"; exit 1; }

step "Replaying the customer's load test"
"$LAB_DIR/tools/load-test.sh" 100 25 | tail -12

cat <<'MSG'

  The ticket is in TICKET.md. Run the same load again any time with:
    ./tools/load-test.sh 100 25
  When you think you've fixed it: ./incidents/03-we-added-workers/verify.sh
MSG
