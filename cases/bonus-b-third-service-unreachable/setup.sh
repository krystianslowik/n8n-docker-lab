#!/usr/bin/env bash
# Prepares the customer's environment. Not part of the puzzle: don't read it.
set -euo pipefail
cd "$(dirname "$0")"

docker compose -f metrics-api/compose.yaml up -d
docker compose up -d
