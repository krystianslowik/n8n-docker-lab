# Queue-mode lab: All containers are running. Unfortunately, so is the incident.

A self-paced n8n queue-mode troubleshooting lab for support engineers. You run a
real deployment (main, two workers, Redis, Postgres and a downstream API) and work
three incidents in which every container stays healthy. For each one, you find where
the execution stopped progressing and what proves it.

The lessons are on a web page. Your lab serves a copy at <http://localhost:5691>
with a live panel, and a hosted copy with the same content may be shared with you.

## Quickstart

You need Docker with Compose v2, 4 GB of memory for Docker, 3.5 GB of disk (less if
you still have the break/fix lab's images), bash, curl, and free ports 5690–5692.
It's tested on macOS and Linux. WSL 2 on Windows should work, but nobody has tried it.

```bash
git clone https://github.com/krystianslowik/n8n-docker-lab.git
cd n8n-docker-lab/queue-mode-session
./setup.sh
```

`setup.sh` ends with `PASS` when the deployment works end to end. Then open:

| What | Where |
|---|---|
| Lessons and live panel | <http://localhost:5691> |
| n8n editor | <http://localhost:5690> (`owner@example.com` / `DockerLab2026`) |
| fulfilment-api counters | <http://localhost:5692/stats> |

## The lessons

| # | Lesson | Start with | Check with |
|---|---|---|---|
| 0 | Trace one order through the deployment | the page | the page's prompts |
| 1 | "It works when I click Execute" | `incidents/01-it-works-when-i-click-execute/setup.sh` | `…/verify.sh` |
| 2 | "Redis returned PONG" | `incidents/02-redis-said-pong/setup.sh` | `…/verify.sh` |
| 3 | "We added workers" (optional) | `incidents/03-we-added-workers/setup.sh` | `…/verify.sh` |

Each incident directory has a `TICKET.md` with the customer's report. Don't read an
incident's `setup.sh` until you're done, because it contains the answer.

Your answers to the page's prompts stay in your browser. Download them from the
Notebook page before the follow-up discussion.

## Reset and recovery

| Command | Configuration | Redis queue | Postgres data |
|---|---|---|---|
| `./reset.sh` | restored from `env/baseline/` (yours saved to `env/before-reset/`) | emptied | kept |
| `./reset.sh --full` | restored | emptied | deleted and seeded again |
| `./teardown.sh` | removes the `qmlab` project's containers, network and volumes | | |

Everything is scoped to the Compose project `qmlab`. The break/fix cases, the
reference stack and your other containers are left alone.

## What's in here

```
compose.yaml            n8n-main, n8n-worker (×2), redis, postgres, fulfilment-api, console
.env, env/              configuration; main.env and worker.env are separate on purpose
env/baseline/           known-good copies that reset.sh restores
setup.sh verify.sh      bring up the baseline and prove it works
reset.sh teardown.sh    get back to known-good, or remove everything
incidents/NN-*/         TICKET.md, setup.sh (the fault), verify.sh (checks the outcome)
tools/evidence.sh       read-only evidence, printing every command it runs
tools/load-test.sh      a burst of orders, then outcome numbers from Postgres and the API
tools/rehearse.sh       for maintainers: full rehearsal from a clean start, records evidence
tools/build-site.sh     for maintainers: builds the hostable page into site-dist/
fulfilment-api/         the downstream service (plain Node, 10 requests at once, then HTTP 429)
console/                the lesson page and its read-only live-state server
seed/                   the "Order intake" workflow and its credential
DEPLOY.md               how to host the page
```

## Pinned versions

n8n `2.33.0`, Postgres `17-alpine`, Redis `7.4.11-alpine`. The fulfilment API and the
console run on the n8n image's Node runtime, so nothing else gets pulled.
`tools/rehearse.sh` reproduces every behaviour the page describes on these versions
and fails if one stops holding. Re-run it after changing the lab or the image.
