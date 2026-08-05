#!/usr/bin/env bash
# Prepares the customer's environment. Don't read this file: it is never part
# of the puzzle. Run it, then run ./verify.sh.
set -euo pipefail
cd "$(dirname "$0")"

log=$(mktemp -t docklab-02-setup)
trap 'rm -f "$log"' EXIT

echo "Preparing the customer's environment (the first run takes a minute)..."

# 1. The database, exactly as it has been running for months.
docker compose up -d --wait postgres >>"$log" 2>&1

# 2. Replay the credential the customer created back then, on the deployment
#    that came before their redeploy. n8n writes its own data here, so this
#    is not a canned dump of anyone's schema.
if ! docker compose run --rm \
      -e N8N_ENCRYPTION_KEY=a1b2c3d4e5f60718293a4b5c6d7e8f90 \
      -v "$PWD/seed:/seed:ro" \
      n8n import:credentials --input=/seed/credentials.json >>"$log" 2>&1; then
  echo "setup failed, output follows:" >&2
  cat "$log" >&2
  exit 1
fi

# 3. The stack as it is deployed today.
docker compose up -d

echo
echo "The customer's stack is up. n8n is on http://localhost:5602"
echo "Log in as owner@example.com / DockerLab2026, see SYMPTOM.md."
