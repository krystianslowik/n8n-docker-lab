#!/usr/bin/env bash
# Incident 01 setup. Prepares the customer's environment on top of a clean
# baseline. Reading this file gives the answer away, so don't, unless you are
# the one running the session.
set -uo pipefail
. "$(dirname "$0")/../../lib/common.sh"
INC=01

step "Incident $INC: restoring the baseline first"
restore_baseline_config quiet

# The customer rebuilt their worker hosts from a template on Tuesday. The
# template generated a fresh key. Main still has the original one.
cat > env/worker.env <<'ENV'
# Role-specific settings for every n8n-worker replica. Main reads env/main.env.
# Anything that must match between the two is marked MUST MATCH.
#
# Regenerated from the infra template during Tuesday's worker rebuild (CHG-4402).

# MUST MATCH: decrypts credentials. Main uses it for manual runs, workers for
# everything else.
N8N_ENCRYPTION_KEY=0f4d8a6c2e1b49d7a3c5e8f6b1d2a4c9

# MUST MATCH: which Redis logical database holds the Bull queue.
QUEUE_BULL_REDIS_DB=0
ENV

apply_config || { bad "the stack did not come up healthy, try ./reset.sh"; exit 1; }
curl -s -X POST "$API_URL/stats/reset" >/dev/null

step "Replaying the customer's morning"
mkdir -p "$STATE_DIR"; echo "$(max_execution_id)" > "$STATE_DIR/$INC.start"
n8n_login
for _ in 1 2 3; do manual_run >/dev/null; done
for ref in SHOP-3301 SHOP-3302 SHOP-3303 SHOP-3304; do send_order "$ref" >/dev/null; done
sleep 6
ok "3 manual test runs and 4 shop orders sent"

cat <<'MSG'

  The ticket is in TICKET.md. Every container is running and healthy.
  Start with: docker compose ps
  When you think you've fixed it: ./incidents/01-it-works-when-i-click-execute/verify.sh
MSG
