# Case 04: "every redeploy still wipes our workflows"

**Ticket:** SUP-4463
**From:** ops@fenwick-analytics.example
**Setup:** self-hosted n8n 2.33.0 + PostgreSQL, Docker Compose, one Linux host
**Severity:** high (not down, but losing work)

---

## What the customer wrote

> We migrated to Postgres weeks ago (our ticket OPS-731) and n8n has been running
> fine ever since. The problem is that every redeploy still wipes our workflows.
> We lost three of them again on Tuesday.
>
> Our deploy script is `docker compose down -v && docker compose up -d`. That was
> always safe before, because the whole point of moving to Postgres was that the
> data lives in the database now, not in a container.
>
> The Postgres container is healthy and we can connect to it by hand, so we don't
> think the database is the problem. n8n starts up completely clean. There is
> nothing red anywhere.

The log lines they pasted, "to show there's nothing wrong":

```
n8n-1  | Version: 2.33.0
n8n-1  | Building workflow dependency index...
n8n-1  | Finished building workflow dependency index. Processed 0 draft workflows, 0 published workflows.
n8n-1  |
n8n-1  | Editor is now accessible via:
n8n-1  | http://localhost:5678
```

## What they already tried

- Confirmed `docker compose ps` shows both containers `Up` and `(healthy)`.
- Connected to the database by hand and listed the tables:

  ```
  n8n=# \dt
  Did not find any relations.
  ```

  They read that as "n8n hasn't created its tables yet" and asked whether there is
  a separate migration command they were supposed to run after the migration.
- Wondered whether n8n is putting its tables in some other schema: OPS-812 in
  their backlog is about splitting schemas per environment, so they suspect that
  is related.
- Restored Monday's Postgres dump. It restored fine and changed nothing.
- Re-entered the database password. No change.

They have attached their `compose.yaml` and `.env`. Those are the two files in
this directory. Assume they are what is actually deployed.

---

## Your job

Boot the customer's stack, reproduce the symptom, find out why, fix it, and prove
it with `./verify.sh`.

```
./setup.sh      # brings up the customer's stack as-is
./verify.sh     # tells you whether it is actually fixed
```

n8n is published on **http://localhost:5604** on this host.
The login is `owner@example.com` / `DockerLab2026`: there is no signup wizard on
this instance.

If you tie yourself in knots, you can always start over from the shipped broken
state. Nothing here is precious:

```
docker compose down -v && ./setup.sh
```

When you're done, be ready to tell the room three things: what you observed,
**which command told you the answer**, and what you changed.
