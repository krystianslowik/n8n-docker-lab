# Case 01: "n8n won't start"

**Ticket:** SUP-4417
**From:** ops@northwind-logistics.example
**Setup:** self-hosted n8n 2.33.0 + PostgreSQL, Docker Compose, one Linux host
**Severity:** production down

---

## What the customer wrote

> n8n won't start. All I get in the logs is `ECONNREFUSED 127.0.0.1:5432`.
> Postgres is definitely running.
>
> The browser just says the site can't be reached. We don't even get an n8n
> error page, so I don't think the app is coming up at all. This worked on
> Friday, nothing was deployed over the weekend as far as I know.

The one log line they pasted:

```
Initial database connection attempt 1 failed: connect ECONNREFUSED 127.0.0.1:5432. Retrying in 1000ms
```

## What they already tried

- Restarted the Postgres container. Twice. "It comes up fine every time."
- Restarted the whole stack.
- Confirmed the Postgres container is up and staying up.
- Checked that nothing else on the host is using port 5432.
- Recreated the n8n container.

They have attached their `compose.yaml` and `.env`: those are the two files in
this directory. Assume they are what is actually deployed.

---

## Your job

Boot the customer's stack, reproduce the symptom, find out why, fix it, and prove
it with `./verify.sh`.

```
./setup.sh      # brings up the customer's stack as-is
./verify.sh     # tells you whether it is actually fixed
```

n8n is published on **http://localhost:5601** on this host.
Once the stack is healthy, the login is `owner@example.com` / `DockerLab2026`.
There is no signup wizard on this instance.

If you tie yourself in knots, you can always start over from the shipped broken
state (nothing here is precious):

```
docker compose down -v && ./setup.sh
```

When you're done, be ready to tell the room three things: what you observed,
**which command told you the answer**, and what you changed.
