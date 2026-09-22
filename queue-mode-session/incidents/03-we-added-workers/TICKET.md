# Incident 03: "We added workers. The queue got worse."

**Priority:** High · **Plan:** Self-hosted Enterprise · **Deployment:** queue mode, Docker Compose · **Optional**

> Black Friday is in three weeks, so we load-tested. Orders were failing, so we
> scaled workers from 2 to 5 and increased concurrency to 200. The dashboard
> says jobs are picked up faster than ever, but more orders fail than before.
>
> **Follow-up:** We increased concurrency to 200. The errors are now
> significantly faster.

**Recent changes:** `--concurrency=200` on the worker command, `WORKER_REPLICAS=5`,
and "a clean-up of the worker env file".

**Proposed next step:** 10 workers.

---

Before you touch anything, write down which number should improve if the workers are
the bottleneck. Then check what concurrency the workers are really running with; the
200 is what the customer put in a file. The fulfilment team says their API "has not
changed in years".


From `queue-mode-session/` (setup runs a 100-order load test):

- Start: `./incidents/03-we-added-workers/setup.sh`
- Measure again: `./tools/load-test.sh 100 25`
- Check your fix: `./incidents/03-we-added-workers/verify.sh`
- Start over: `./reset.sh`
