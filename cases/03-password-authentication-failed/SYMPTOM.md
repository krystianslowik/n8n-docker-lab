# Case 03: "password authentication failed for user n8n"

**Ticket #4712 · Acme Retail GmbH · self-hosted n8n 2.33.0 + PostgreSQL 17 · Docker Compose on one VM**

## What the customer reports

> Our n8n stopped coming up. The container starts, sits there for about half a
> minute, and then it's gone. Nothing on port 5603 at all. The browser just says
> the connection was refused, we don't even get an error page.
>
> We went looking in the database logs and found this:
>
> ```
> FATAL:  password authentication failed for user "n8n"
> ```
>
> We have checked that password three times. It is correct. It's in our .env, it's
> the password we set the database up with, and we can see it in the file with our
> own eyes.

## What they have already tried

- Restarted the stack "at least ten times".
- Restarted only the database container. It comes up fine and reports healthy.
- Confirmed the database container is running and healthy in `docker compose ps`.
- Re-read `.env` and confirmed the password there is the one they intended.
- Their last message: *"if the password is wrong, why does it try five times before
  it gives up? That looks like a network problem to us, not a password problem."*

## Your job

Find out why the database is rejecting that user, fix it, and be able to say which
command told you.

Nothing in this case needs a browser, but once it is fixed the UI is at
<http://localhost:5603> and the owner login is `owner@example.com` /
`DockerLab2026`.

```
cd cases/03-password-authentication-failed
./setup.sh
./verify.sh
```

If you tie yourself in knots, reset to the shipped broken state with:

```
docker compose down -v && ./setup.sh
```

Hints land in this directory before the session (`HINT-1.txt` through `HINT-3.txt`).
Until then it is you, the logs, and `./verify.sh`.

---

When you're done, be ready to tell the room three things: what you observed,
**which command told you the answer**, and what you changed.
