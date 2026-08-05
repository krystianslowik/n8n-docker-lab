# The diagnostic command kit

One page. Run these from inside a case directory (or `reference/`): `docker compose`
finds the project from the `compose.yaml` next to you.

Everything quoted below is real output from the `reference/` stack on
`n8n:2.33.0` + `postgres:17-alpine`, Docker Engine 29.2.1 / Compose v5.1.0, macOS.

---

## 1. Is it running?

```bash
docker compose ps          # RUNNING containers only
docker compose ps -a       # ...and the exited / created ones. Use this one.
docker compose ps -a --format '{{.Service}}: {{.Status}}'
docker compose ls          # every Compose PROJECT on this machine
docker ps                  # every container on this machine, any project
```

`docker compose ps` without `-a` **hides exited containers entirely**, which reads as
"the service never started". It also only ever shows *this* project.

Four states, four different problems:

| State | Means |
|---|---|
| `Up … (healthy)` | running, and its healthcheck is passing |
| `Exited (1)` | it ran, decided it could not continue, and quit. There will be logs. |
| `Restarting (1)` | the above, on a loop, because of `restart:` |
| `Created` | the container exists and has **never executed an instruction**. No logs at all. |

## 2. What does it say: both sides, always

```bash
docker compose logs --tail=50 n8n
docker compose logs -f n8n              # follow, while you reproduce
docker compose logs n8n | head -20      # the TOP of the log
docker compose logs postgres            # the other container. Every time.
docker compose logs --since=2m          # both services, interleaved
```

`--tail` is a habit, not a strategy. A healthy first boot in this lab is around
**500 lines** (measured: 495 on the reference stack) and the interesting line is
sometimes line 1. Read the top as well as the bottom.

The service that *reports* an error and the service that *caused* it are often
different containers.

## 3. Is the name resolvable?

Inside a container, `localhost` is **that container**. The service name is the DNS
name, resolved by Docker's embedded DNS at `127.0.0.11`.

```bash
docker compose exec n8n nslookup postgres
docker compose exec n8n ping -c 2 postgres
docker compose exec n8n node -e "require('dns').lookup('postgres',(e,a)=>console.log(e?e.message:a))"
docker network ls
docker network inspect <net-a> <net-b> --format '{{.Name}}: {{range .Containers}}{{.Name}} {{end}}'
docker inspect <container> --format '{{range $k,$v := .NetworkSettings.Networks}}{{$k}} {{$v.IPAddress}}{{"\n"}}{{end}}'
```

Two failures that look alike and are not:

| Error | Means |
|---|---|
| `ECONNREFUSED 127.0.0.1:5432` | the name resolved; **nothing is listening there**. Config problem. |
| `ENOTFOUND postgres` / `bad address` | the name did not resolve. Compose DNS only answers for **running** containers on a **shared network**. Availability or topology problem. |

Measured: with Postgres stopped, `dns.lookup('postgres')` from inside n8n returns
`getaddrinfo ENOTFOUND postgres`, and the n8n log fills with
`Database ping failed (1/3): getaddrinfo ENOTFOUND postgres`.

**What is in the n8n image**, verified. This matters when you are reaching for a tool:

```
present:  wget  ping  nc  netstat  nslookup  ip  node  npm
ABSENT:   curl  psql  dig  getent  ss  telnet  python3
```

So: HTTP checks inside the container use `wget` or `node -e`, never `curl`. Reach
Postgres with `docker compose exec postgres psql -U n8n -d n8n`, never from the n8n
container.

## 4. Is anything listening, and does it actually work?

```bash
docker compose exec n8n netstat -ltn          # listening sockets INSIDE the container
docker compose port n8n 5678                  # -> 0.0.0.0:5678   what the HOST maps
docker ps --filter publish=5678               # which container holds a host port
curl -s http://localhost:<hostport>/healthz
curl -s -o /dev/null -w '%{http_code}\n' http://localhost:<hostport>/healthz/readiness
```

The container port and the host port are two different facts. n8n always listens on
**5678 inside**; the left-hand side of `"5601:5678"` is the only part you chose.

### `/healthz` versus `/healthz/readiness`: the one to internalise

Measured on the reference stack with **Postgres stopped**:

```
$ docker compose ps -a --format '{{.Service}}: {{.Status}}'
n8n: Up 56 seconds (healthy)          <-- still says healthy
postgres: Exited (0) 3 seconds ago

$ curl -s -w ' [http %{http_code}]\n' http://localhost:5678/healthz
{"status":"ok"} [http 200]            <-- liveness lies, by design

$ curl -s -w ' [http %{http_code}]\n' http://localhost:5678/healthz/readiness
{"status":"error"} [http 503]         <-- readiness tells the truth
```

- **`/healthz` returns 200 unconditionally and deliberately ignores the database.** It
  answers "is this process alive", nothing more. It is not a health check for anything
  that matters, and any monitoring built on it will report green through an outage.
- **`/healthz/readiness` returns 200 only when the database is connected *and*
  migrated.** It also returns 503 transiently during migrations, so poll it in a loop
  rather than reading it once. Neither endpoint needs auth.
- **`(healthy)` in `docker compose ps` is a lagging indicator.** Above, the container
  still claimed healthy with no database at all; the healthcheck needs up to
  `interval × retries` to notice. Never treat it as ground truth.
- A 200 tells you *something* answered, not that the right something answered. In
  case 05, Adminer cheerfully returns 200 for `/healthz/readiness` (it is a PHP server
  serving its login page). Check the body, not just the code.

## 5. ★ Is the config what you think it is?

```bash
docker compose config                      # the FULLY RESOLVED file, after .env interpolation
docker compose config | grep -iE 'DB_|PASSWORD|published'
docker inspect <container> --format '{{range .Config.Env}}{{println .}}{{end}}'
docker compose exec n8n printenv DB_TYPE
```

**This is the command most people have never run, and it settles env-precedence
arguments instantly.** `compose.yaml` might say
`DB_POSTGRESDB_HOST: ${POSTGRES_HOST}`. The actual value is one file away, and
`config` is what merges them:

```
$ docker compose config | grep -E 'DB_POSTGRESDB_HOST|DB_TYPE'
      DB_POSTGRESDB_HOST: postgres
      DB_TYPE: postgresdb
```

Three variants, and the differences matter:

- **`docker compose config`**: what Compose resolved from the files. Works when the
  container is dead.
- **`docker inspect … .Config.Env`**: what *this particular container* was actually
  handed at creation. Also works on a dead container. When these two disagree, you
  have found something: the container predates your edit.
- **`docker compose exec … printenv`**: what a *live* process was handed. Needs a
  running container, and `exec` against a dead one just says
  `service "n8n" is not running`.

None of the three tells you what the process **did** with the value. A value that
fails validation can be discarded, warned about once, and replaced by a default. See
case 04. `printenv` showing your value is not proof your config took effect.

**The best version of this command is a diff against something known-good:**

```bash
diff <(docker compose -f ../../reference/compose.yaml config) <(docker compose config)
```

That cancels out comments, quoting, key order and `.env` indirection. What survives
the diff is semantics.

*Aside, so it doesn't derail you:* `docker compose config` prints a literal `$` as
`$$` (e.g. the owner hash as `$$2a$$10$$…`). That is Compose escaping its own output
so it can be fed back in. The container receives single dollars, verified with
`printenv` inside it.

## 6. Is the state older than the config?

Volumes outlive containers, environment variables and your edits.

```bash
docker volume ls --filter name=docklab
docker volume inspect docklab-01_n8n_data
docker compose exec n8n ls -la /home/node/.n8n/
docker compose exec postgres psql -U n8n -d n8n -c '\dt'
docker compose down          # keeps volumes
docker compose down -v       # deletes THIS project's volumes. Destroys data.
```

Two facts from this lab worth carrying:

- `POSTGRES_PASSWORD` is read **once**, by `initdb`, when the volume is created. After
  that the password lives in the volume and the environment variable is decoration.
- `N8N_ENCRYPTION_KEY` is written into `/home/node/.n8n/config` on first boot. Lose
  the volume and you lose the key; keep the volume with a *different* key in the
  environment and n8n refuses to start at all.

`down -v` only removes volumes the **current** compose file declares. A volume you
added and then removed from the file keeps existing, unreferenced. Same for
containers: `docker compose down --remove-orphans` is what clears a service you
deleted from the file.

## 7. Only now: change one thing

```bash
docker compose up -d          # RECREATES containers whose definition changed
docker compose restart n8n    # restarts the SAME container, with the SAME env
```

An environment or image change needs `up -d`. `restart` re-runs the old container with
the old environment, and it is the reason people who are already right about the fix
still see the bug. Look for `Recreated` in the output, not `Started`.

---

## Warnings that are expected and benign

Do not chase these. Verified present on a clean, healthy boot of every stack in this
lab.

**n8n prints four of them, on every boot** (cold or warm):

```
Failed to start Python task runner in internal mode. because Python 3 is missing from this system. Launching a Python runner in internal mode is intended only for debugging and is not recommended for production. Users are encouraged to deploy in external mode. See: https://docs.n8n.io/hosting/configuration/task-runners/#setting-up-external-mode
(node:7) DeprecationWarning: Calling client.query() when the client is already executing a query is deprecated and will be removed in pg@9.0. Use async/await or an external async flow control mechanism instead.
(Use `node --trace-deprecation ...` to show where the warning was created)
[license SDK] Skipping renewal on init: license cert is not initialized
```

The Python one cannot be removed without adding a task-runner sidecar, which this
two-service lab deliberately does not do. Note that `[license SDK] …` does not match
`grep -i 'warn\|error\|fail'`, so a grep-only pass misses it. And then someone finds
it later and panics.

**Postgres prints two more, on first boot only** (`initdb`, before the volume exists):

```
WARNING:  no usable system locales were found
initdb: warning: enabling "trust" authentication for local connections
```

Also benign, and worth knowing:

- `Last session crashed` on the first line of a boot: n8n noticing the crash you just
  fixed, recorded in its volume. Not a new problem.
- `Editor is now accessible via: http://localhost:5678`. 5678 is the port *inside*
  the container. n8n has no idea it was published on 5601. (Bonus case A is about
  exactly this, and there it is not benign.)
- 200-odd `Starting migration … / Finished migration …` pairs on a cold boot. That is
  n8n creating its schema, and it is why the first boot takes longest.

**Telling benign noise from signal is the skill.** Two of these lines appear in real
tickets every week, pasted by customers as "the only error we can find".

---

## The seven-rung ladder, in one block

```
1. Is it running?                docker compose ps -a
2. What does it say?             docker compose logs --tail=50 <svc>   ...both sides, head AND tail
3. Is the name resolvable?       service name, never localhost
4. Is anything listening?        netstat inside vs. compose port outside; /healthz/readiness
5. Is the config real?           docker compose config      <-- the one nobody runs
6. Is the state older?           docker volume ls; down -v is destructive
7. Change ONE thing              docker compose up -d, re-check
```
