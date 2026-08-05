# Ticket #4835: "n8n can't reach our third service by name"

**Customer:** Acme Freight, integrations team
**Environment:** self-hosted n8n 2.33.0 + PostgreSQL 17, Docker Compose on one VM.
n8n is published on host port 5611.

## What they reported

> We added a third service alongside n8n and Postgres. It's an internal metrics API.
> Our workflows call it at `http://metrics-api/` and every single call fails with a
> DNS error. The container is definitely running, `docker ps` says it's up and
> healthy. n8n itself is completely fine: we can log in, Postgres is fine, nothing
> is crash-looping. It's just this one hostname that doesn't exist as far as n8n is
> concerned. Is `metrics-api` a reserved name or something?

## What they already tried

- Restarted the metrics container, then the whole n8n stack, then Docker itself
  for good measure.
- Confirmed the metrics API answers on port 80 *inside its own container*. It
  returns the nginx page, so the service works.
- Triple-checked the hostname for typos, including in the workflow.
- Bumped n8n to the newest tag on their staging box. Same behaviour.

## The output they pasted

Their engineer ran this from inside the n8n container:

```
$ docker compose exec n8n wget -qO- http://metrics-api/
wget: bad address 'metrics-api'
```

…and this, to show us the container is up:

```
$ docker ps
NAMES                                   IMAGE                            STATUS
docklab-bonus-b-n8n-1                   docker.n8n.io/n8nio/n8n:2.33.0   Up 30 seconds (healthy)
docklab-bonus-b-postgres-1              postgres:17-alpine               Up 36 seconds (healthy)
docklab-bonus-b-metrics-metrics-api-1   nginx:alpine                     Up 37 seconds (healthy)
```

Nothing in `docker compose logs n8n` mentions the metrics API at all.

## Your job

Make n8n able to reach `http://metrics-api/` by name, from inside the n8n
container. Then run `./verify.sh`.

The n8n UI is at <http://localhost:5611> if you want to poke at the instance:
log in as `owner@example.com` / `DockerLab2026`. You do not need it to solve this.

If you tie yourself in knots, reset with:

```
docker compose down -v && ./setup.sh
```

When you're done, be ready to tell the room three things: what you observed,
**which command told you the answer**, and what you changed.
