# Bonus A: "every webhook URL n8n gives us is wrong"

**Ticket:** SUP-5102
**From:** ops@brightline-payments.example
**Setup:** self-hosted n8n 2.33.0 + PostgreSQL, Docker Compose, one Linux host
**Severity:** high (integrations broken, instance itself is up)

---

## What the customer wrote

> We moved n8n off port 5678 back in February because the old single-container
> box on this host still owns that port. It's published on **5610** now, and the
> editor works perfectly on http://localhost:5610. We're logged in and using it
> all day.
>
> The problem is every URL n8n *hands out* still says `:5678`. Open any Webhook
> node and the production URL it shows you is
> `http://localhost:5678/webhook/…`. Our payment provider can't call that: they
> get connection refused. If I take the same path and put `:5610` on it by hand,
> it works first time, so the workflow is fine and the port mapping is fine.
> It's the URL n8n *prints* that is wrong.
>
> Right now three people are copying URLs out of n8n and editing the port in a
> text editor before sending them to anyone. That is not a long-term plan.

The one log line they pasted:

```
Editor is now accessible via:
http://localhost:5678
```

## What they already tried

- Restarted the stack. Recreated both containers.
- Confirmed `docker compose ps` really does show 5610 published.
- Checked the host firewall.
- Cleared the browser cache, "in case the UI was showing us something stale".
- Searched their compose file for `5678`. They found the right-hand side of the
  port mapping, changed it, and everything broke, so they changed it back. Their
  words: *"that side is correct, it's the number inside the container."*

They have attached their `compose.yaml` and `.env`, the two files in
this directory. Assume they are what is actually deployed.

---

## Your job

Boot the customer's stack, reproduce the symptom, find out why, fix it, and prove
it with `./verify.sh`.

```
./setup.sh      # brings up the customer's stack as-is
./verify.sh     # tells you whether it is actually fixed
```

n8n is published on **http://localhost:5610** on this host.
The login is `owner@example.com` / `DockerLab2026`. There is no signup wizard on
this instance, and you will want it: some of what is wrong here is only visible
to a logged-in user.

If you tie yourself in knots, you can always start over from the shipped broken
state. Nothing here is precious:

```
docker compose down -v && ./setup.sh
```

When you're done, be ready to tell the room three things: what you observed,
**which command told you the answer**, and what you changed.
