#!/usr/bin/env bash
# Brings up the known-good queue-mode deployment and proves it works.
#
#   ./setup.sh
#
# Safe to re-run. The first run pulls images, creates the database, imports the
# "Order intake" workflow and its credential, and publishes the workflow. Later
# runs skip the import because the workflow is already there.
#
# It does NOT restore configuration you changed. That is ./reset.sh.
set -uo pipefail
. "$(dirname "$0")/lib/common.sh"

step "1/4  Pulling images (first run only takes a while)"
docker compose pull --quiet 2>&1 | grep -v '^$' || true
ok "images present: n8n 2.33.0, postgres 17-alpine, redis 7.4.11-alpine"

step "2/4  Starting Postgres, Redis, fulfilment-api and the console"
docker compose up -d postgres redis fulfilment-api console >/dev/null 2>&1
wait_healthy postgres 120 && wait_healthy redis 60 && wait_healthy fulfilment-api 60 \
	|| { bad "a dependency did not become healthy. Try: docker compose ps; docker compose logs postgres redis"; exit 1; }
ok "postgres, redis and fulfilment-api are healthy"

step "3/4  Seeding the workflow"
seeded=$(psql_q "SELECT COUNT(*) FROM workflow_entity WHERE id = '$WORKFLOW_ID';" || echo 0)
if [ "${seeded:-0}" = "1" ]; then
	ok "\"Order intake\" already imported, skipping"
else
	# One-off containers from the main service definition, so they get exactly
	# main's database settings and encryption key. The first one also runs
	# n8n's database migrations.
	run_cli() { docker compose run --rm --no-deps -T -v "$LAB_DIR/seed:/seed:ro" n8n-main "$@" >/tmp/qmlab-seed.log 2>&1; }
	run_cli import:credentials --input=/seed/credentials.json \
		|| { bad "credential import failed, see /tmp/qmlab-seed.log"; exit 1; }
	run_cli import:workflow --input=/seed/workflows.json \
		|| { bad "workflow import failed, see /tmp/qmlab-seed.log"; exit 1; }
	run_cli publish:workflow --id="$WORKFLOW_ID" \
		|| { bad "publishing the workflow failed, see /tmp/qmlab-seed.log"; exit 1; }
	ok "imported credential \"Fulfilment API key\" and published workflow \"Order intake\""
fi

step "4/4  Starting n8n-main and the workers"
docker compose up -d >/dev/null 2>&1
wait_healthy n8n-main 240 || { bad "n8n-main did not become ready. Try: docker compose logs --tail=40 n8n-main"; exit 1; }
wait_healthy n8n-worker 180 || { bad "a worker did not become ready. Try: docker compose logs --tail=40 n8n-worker"; exit 1; }
ok "n8n-main and $(worker_count) worker(s) are healthy"

echo
exec "$LAB_DIR/verify.sh"
