#!/usr/bin/env bash
# Incident 02 setup. Prepares the customer's environment on top of a clean
# baseline. Reading this file gives the answer away.
set -uo pipefail
. "$(dirname "$0")/../../lib/common.sh"
INC=02

step "Incident $INC: restoring the baseline first"
restore_baseline_config quiet

# The customer moved n8n to its own Redis logical database so another app's
# keys stop mixing with theirs. The change went into main's file only.
cat > env/main.env <<'ENV'
# Role-specific settings for n8n-main. Workers read env/worker.env instead.
# Anything that must match between the two is marked MUST MATCH.

# MUST MATCH: decrypts credentials. Main uses it for manual runs, workers for
# everything else.
N8N_ENCRYPTION_KEY=5b9e2c71d04a4f8e9a61c3f0b7d28e14

# MUST MATCH: which Redis logical database holds the Bull queue.
# Moved to DB 1 so the billing app's keys stop mixing with ours (CHG-4471).
QUEUE_BULL_REDIS_DB=1
ENV

apply_config || { bad "the stack did not come up healthy, try ./reset.sh"; exit 1; }
curl -s -X POST "$API_URL/stats/reset" >/dev/null

step "Replaying the customer's afternoon"
mkdir -p "$STATE_DIR"; echo "$(max_execution_id)" > "$STATE_DIR/$INC.start"
for ref in SHOP-4401 SHOP-4402 SHOP-4403 SHOP-4404 SHOP-4405; do send_order "$ref" >/dev/null; done
sleep 3
echo "$(max_execution_id)" > "$STATE_DIR/$INC.end"
ok "5 shop orders sent. The shop got HTTP 200 for every one."

cat <<'MSG'

  The ticket is in TICKET.md. Five customer orders are somewhere in this system,
  and verify.sh checks what your fix did to them.
  When you think you've fixed it: ./incidents/02-redis-said-pong/verify.sh
MSG
