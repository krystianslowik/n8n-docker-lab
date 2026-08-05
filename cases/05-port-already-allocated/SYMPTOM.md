# Case 05: "our stack will not come up at all any more"

**Ticket #4471 · Fernbrook Freight · self-hosted n8n on their own ops VM**

---

> We rebuilt our ops VM last week and copied the same compose file across. Since
> then the stack will not come up at all. n8n never appears on 5605.
>
> I have rebooted the VM twice. I also checked that nothing else on the machine
> is listening on 5605. Nothing is. Docker just prints this and gives up:
>
> ```
> Error response from daemon: failed to set up container networking: driver failed programming external connectivity on endpoint docklab-05-n8n-1 (2ff3216a0a98b9ee8e9a3a06190106919cb5b018b217556618452ef1e31b0c5b): Bind for 0.0.0.0:5605 failed: port is already allocated
> ```
>
> Please can you get n8n back? It has to stay on 5605, that is the only port the
> office firewall lets through. The data team need their database UI as well.
>
> Marek, Fernbrook Freight

---

## What "fixed" means here

Every service in the customer's file running, n8n answering on
<http://localhost:5605>, and the database UI still reachable from a browser.

## Working on this case

- `./setup.sh`: puts the customer's environment back the way they have it.
  **Run it again after every change you make**; it recreates the containers.
  A bare `docker compose up -d` can re-use a container that Docker never
  managed to start properly, and then you are debugging a ghost.
- `./verify.sh`: tells you whether you are done. It checks the running stack,
  not your edits.
- Full reset, data and all: `docker compose down -v && ./setup.sh`

## Login, if you want the UI

`owner@example.com` / `DockerLab2026`

## Report back

Be ready to tell the room three things: what you observed, **which command told
you the answer**, and what you changed.
