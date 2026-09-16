# Incident 01: "It works when I click Execute"

**Priority:** High (set by the customer) · **Plan:** Self-hosted Enterprise · **Deployment:** queue mode, Docker Compose

> Since Tuesday our shop orders are not reaching fulfilment. We have tested the
> workflow in the editor and it works every time, so queue mode is working and
> this must be a bug in the webhook node.
>
> **Follow-up, 40 minutes later:** We tested it seventeen times. Please escalate.

**Recent changes:** "Nothing related. Infra rebuilt the worker hosts on Tuesday but
that was routine."

**Attached:** a screenshot of a green manual execution.

---

Find out which process ran those seventeen tests, and which process handles a real
shop order.


From `queue-mode-session/`:

- Start: `./incidents/01-it-works-when-i-click-execute/setup.sh`
- Check your fix: `./incidents/01-it-works-when-i-click-execute/verify.sh`
- Start over: `./reset.sh`
