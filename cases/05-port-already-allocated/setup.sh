#!/usr/bin/env bash
# Prepares the customer's environment. Don't read this: it is never part of
# the puzzle. When you think you have fixed the case, run ./verify.sh
set -uo pipefail
cd "$(dirname "$0")"

# Start from the customer's containers as they were, so every run of this
# script does the same thing. Volumes are kept.
docker compose down --remove-orphans >/dev/null 2>&1

docker compose up -d
