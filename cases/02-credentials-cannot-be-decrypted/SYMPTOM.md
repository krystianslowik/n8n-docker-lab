# Case 02: "every credential is empty since the redeploy"

**Ticket:** SUP-4602
**From:** it@acme-interiors.example
**Setup:** self-hosted n8n 2.33.0 + PostgreSQL, Docker Compose, single host
**Severity:** production impaired, nothing is running on schedule

---

## What the customer wrote

> After our redeploy, every credential we open shows empty fields. Nothing
> works. We did not touch the credentials.
>
> They are all still listed, with the right names, so the data is clearly there.
> But when I click into one, every field is blank, as if someone had wiped
> them. The workflows that use them just fail.
>
> We moved n8n to a new host last week. Same version, same database, we brought
> the compose file over and rebuilt it. Nobody has been near the credentials.

The one log line they pasted, "the only error we can find":

```
Failed to start Python task runner in internal mode. because Python 3 is missing from this system. Launching a Python runner in internal mode is intended only for debugging and is not recommended for production. Users are encouraged to deploy in external mode. See: https://docs.n8n.io/hosting/configuration/task-runners/#setting-up-external-mode
```

## What they already tried

- Restarted both containers, then recreated them. No change.
- Re-pulled the image, in case it was a bad build.
- Created a brand-new credential as a test: "that one saves and works fine,
  so n8n itself seems OK?"
- Their DBA checked the database directly: "the rows are all still in
  `credentials_entity`, and the data column looks like gibberish, but our
  understanding is that it always did."
- Restored yesterday's Postgres backup onto a scratch host. Same result.

They have attached their `compose.yaml` and `.env`. Those are the two files in
this directory. Assume they are what is actually deployed. Anything else they
sent us is in `customer-provided/`.

---

## Your job

Boot the customer's stack, reproduce the symptom, find out why, fix it, and
prove it with `./verify.sh`.

```
./setup.sh      # brings up the customer's environment as it is today
./verify.sh     # tells you whether it is actually fixed
```

n8n is published on **http://localhost:5602** on this host. The login is
`owner@example.com` / `DockerLab2026`. There is no signup wizard on this
instance. You will want the UI for this one: open **Credentials** in the left
sidebar and click into `Acme API Header Auth`.

If you tie yourself in knots, you can always start over from the shipped broken
state. Nothing here is precious:

```
docker compose down -v && ./setup.sh
```

When you're done, be ready to tell the room three things: what you observed,
**which command told you the answer**, and what you changed.
