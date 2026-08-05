#!/usr/bin/env bash
# Brings up the customer's stack exactly as they run it. Not part of the puzzle.
set -uo pipefail
cd "$(dirname "$0")"
docker compose up -d
