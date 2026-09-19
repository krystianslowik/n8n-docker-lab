# Incident 02: "Redis returned PONG"

**Priority:** Urgent · **Plan:** Self-hosted Enterprise · **Deployment:** queue mode, Docker Compose

> Since this afternoon no workflow executions finish. They appear in the list and
> never complete. The shop gets HTTP 200 back from the webhook, so n8n is receiving
> the orders.
>
> We can connect to Redis from every container. We ran `redis-cli ping` in the
> Redis container and got PONG, and the worker health checks are all green.
>
> **Follow-up:** Redis returned PONG, so we have ruled out Redis. Is this the
> Bull bug from the forum?

**Recent changes:** "A tidy-up. We gave n8n its own Redis database so the billing
app's keys stop mixing with ours (CHG-4471)."

---

Work out what their evidence actually covers. Then find where main is putting work
and where the workers are looking for it. Five real orders arrived during the
incident, and `verify.sh` checks what your fix did to them.


From `queue-mode-session/`:

- Start: `./incidents/02-redis-said-pong/setup.sh`
- Check your fix: `./incidents/02-redis-said-pong/verify.sh`
- Start over: `./reset.sh`
