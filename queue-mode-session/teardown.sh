#!/usr/bin/env bash
# Removes the queue-mode lab: its containers, network and three volumes.
#
# Scoped to the Compose project "qmlab" (the `name:` in compose.yaml). It never
# touches the break/fix cases, the reference stack, or anything else of yours.
set -uo pipefail
cd "$(dirname "$0")" || exit 1
docker compose down -v --remove-orphans
rm -rf incidents/.state
echo "Done. Images stay cached; ./setup.sh brings the lab back."
