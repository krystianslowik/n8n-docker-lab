# Docker Office Hours: Session 2, the break/fix lab

Seven deliberately broken n8n + PostgreSQL Compose stacks. Each one is written as a
real self-hosted support ticket: a customer's compose file, a customer's `.env`, a
customer's symptom, and a customer's confident wrong theory about the cause.

You will not build anything today. You will diagnose.

The fix is trivia: most of them are one line. The path is the skill. Everything in
this repo is arranged around the one question you have to be able to answer at the
end of your slot:

> **Which command told you the answer?**

"We fiddled until it worked" does not count.

---

## Pre-work: two commands

```bash
git clone https://github.com/krystianslowik/n8n-docker-lab.git && cd n8n-docker-lab
docker compose -f reference/compose.yaml pull
```

That is it. No `.env` to copy, no build step, nothing to install beyond Docker
Desktop (or Docker Engine + the Compose plugin). It pulls the two images every case
uses: `docker.n8n.io/n8nio/n8n:2.33.0` and `postgres:17-alpine`.

Two of the seven cases add one small extra image on first run: `adminer:5.5.1` for
case 05, `nginx:alpine` for bonus-b. They pull in a couple of seconds. If you are
somewhere with bad wifi, get them ahead of time:

```bash
docker compose -f cases/05-port-already-allocated/compose.yaml pull
docker compose -f cases/bonus-b-third-service-unreachable/metrics-api/compose.yaml pull
```

If you skip the pre-work entirely you will be fine. The first ten minutes of the
session are the safety net.

---

## Step one: boot the stack that works

Before anyone debugs anything, everyone runs the known-good stack.

```bash
cd reference
docker compose up -d
./verify.sh
```

Expected:

```
✓ both containers running
✓ n8n ready on http://localhost:5678/healthz/readiness
✓ owner login works (owner@example.com / DockerLab2026)
✓ n8n schema present in Postgres
PASS: reference stack healthy, open http://localhost:5678
```

This does three jobs. It proves your laptop can run the lab before you are asked to
debug it. It absorbs anyone who skipped the pre-work. And it hands you a canonical
correct stack to diff your broken one against, which is itself one of the
techniques the session is teaching:

```bash
# from inside a case directory
diff ../../reference/compose.yaml compose.yaml

# better: diff what Compose actually RESOLVED, which cancels out comments,
# quoting style and .env indirection, leaving only semantics
diff <(docker compose -f ../../reference/compose.yaml config) <(docker compose config)
```

Leave the reference stack running. It costs you nothing and it is the control in
every experiment you run today. `reference/compose.yaml` is also commented
line-by-line with *why* each setting is there. It is the second-best thing in this
repo to take home.

---

## How every case works

Every case works exactly the same way. There are no per-case instructions.

```bash
cd cases/01-cannot-reach-database
cat SYMPTOM.md      # the ticket
./setup.sh          # prepares the customer's environment
./verify.sh         # PASS / FAIL
```

Four rules about those files:

- **Don't read `setup.sh`.** It prepares the customer's environment and is never
  part of the puzzle. Nothing is hidden from you there that matters.
- **`verify.sh` checks reality, not intent.** It looks at the running stack: is the
  container up, does readiness answer, is the data where it should be. It never
  checks which file you edited or what you typed. If you find a fix nobody expected
  and it genuinely works, it passes, and it counts.
- **Read `verify.sh` if you like.** It is ~15 lines and self-contained on purpose.
- **You cannot brick a case.** `docker compose down -v && ./setup.sh` returns a case
  to its shipped broken state, from scratch, as many times as you like. Break things
  freely. That is cheaper than being careful.

After you change a file, re-run `./setup.sh` (or `docker compose up -d`).
`docker compose restart` is **not** enough for an environment change. It restarts
the same container with the environment it was created with. Watch for `Recreated`
in the output, not `Started`.

---

## Rules of engagement

1. **Every case works the same way**: `./setup.sh`, then `./verify.sh`. Don't read
   `setup.sh`.
2. **Hints arrive before the session, not yet.** Right now it is you, the logs, and
   `./verify.sh`. Closer to the day, each case gains `HINT-1.txt`, `HINT-2.txt`,
   `HINT-3.txt` plus a password-protected `FIX.zip`. On the day: no hints for the
   first five minutes, then read them in order: one at a time, go and try it, come
   back before opening the next. No hint contains a fix, a filename, or a value; the
   most any of them does is name what to look at.
3. **You must be able to name the one command that cracked it.** This is the whole
   session. The facilitator writes each group's cracking command on the board during
   report-backs, so the room assembles the toolkit collectively.
4. **Change one thing at a time**, and re-check after each change. Two simultaneous
   changes mean you no longer know which one did anything.
5. **Read both containers' logs.** Not one. This is worth its own rule because it is
   the single most common thing missing from a real support ticket.

**Report-back shape**, 4 minutes per group: 60s what you observed, 90s how you found
it, 60s the fix, 30s questions.

---

## Log in

Every stack in this repo (reference and all seven cases) ships with a
pre-provisioned owner, so there is no setup wizard between `./setup.sh` and the
symptom:

```
owner@example.com  /  DockerLab2026
```

---

## Ports

Every case declares its own Compose project name and its own host port, so two
groups sitting next to each other never collide, and you can run several stacks at
once.

| Stack | URL |
|---|---|
| `reference/` | http://localhost:5678 |
| `cases/01-cannot-reach-database` | http://localhost:5601 |
| `cases/02-credentials-cannot-be-decrypted` | http://localhost:5602 |
| `cases/03-password-authentication-failed` | http://localhost:5603 |
| `cases/04-data-not-in-postgres` | http://localhost:5604 |
| `cases/05-port-already-allocated` | http://localhost:5605 |
| `cases/bonus-a-webhook-url-wrong` | http://localhost:5610 |
| `cases/bonus-b-third-service-unreachable` | http://localhost:5611 |

Case 05 is the deliberate exception: it collides with **itself**, inside its own
compose file, so it reproduces identically no matter what else is running on your
laptop.

---

## Answers

Each case gets a password-protected `FIX.zip` before the session: the diagnostic
path with real output at every step, the root cause, the exact fix, and how the same
bug shows up in real tickets.

Passwords are per case, and the facilitator has them. Ask if you are properly stuck;
that is what they are for. Reading the answer to a case you were never assigned is
the one reliable way to waste the hour.

---

## Read this before you copy anything home: the committed `.env` files

**Every `.env` in this repo is committed to git and working, on purpose.** There are
no `.env.example` files and no copy step.

That directly contradicts the habit session 1 taught (*never commit your `.env`*),
and it is called out here rather than left as a silent bad example. Two reasons for
the choice:

- Pre-work has to stay two commands. A missing `.env` means a copy step, and someone
  will miss it.
- With no `.env` present, `docker compose pull` greets you with a wall of
  unset-variable warnings that read as errors when you are already nervous.

These files hold throwaway lab credentials: a Postgres password of
`n8n-lab-password`, an encryption key of `a1b2c3d4…`, a demo owner login. Nothing in
them has any value anywhere outside this repo, and nothing here is reachable from
the internet.

In real life: `.env` goes in `.gitignore`, secrets come from a secret manager or your
platform's secret store, and `N8N_ENCRYPTION_KEY` gets backed up *with the database*.
Case 02 is what happens when it isn't.

One genuinely load-bearing detail you should copy home, visible in `reference/.env`:

```bash
N8N_OWNER_PASSWORD_HASH='$2a$10$4v9JUCUfjGW4EtaNflZJq.yzr/v48SKstzMg9dGNJjMhmRSQs9Az6'
```

**The single quotes matter.** Compose interpolates `$VAR` sequences inside *unquoted*
`.env` values, and a bcrypt hash is full of `$`. Unquoted, that value can be silently
truncated to `$2a$10`, and login then fails with nothing in any log to tell you why.

---

## The one-page kit

[`CHEATSHEET.md`](CHEATSHEET.md): the diagnostic command kit, plus the list of boot
warnings that are **expected and benign** in this stack. Read that list before you
chase a warning. Four of them appear on every healthy n8n boot in this lab, and a
group that spends ten minutes on the Python task-runner line has been failed by the
material, not by themselves.

---

## Cleaning up

```bash
./tools/teardown.sh
```

Runs `docker compose down -v --remove-orphans` in the reference directory and in
every case directory, and nothing else. It is scoped by Compose project name, so it
touches only this lab's containers, volumes and networks. There is deliberately no
`docker system prune` anywhere in this repo. Deleting your unrelated Docker state is
not this lab's business.

To reset a single case instead, from inside that case directory:

```bash
docker compose down -v && ./setup.sh
```

---

## Layout

```
n8n-docker-lab/
├── README.md                  you are here
├── CHEATSHEET.md              one-page diagnostic command kit
├── reference/                 the known-good stack, boot this first
│   ├── compose.yaml           heavily commented; the best thing here to take home
│   ├── .env
│   └── verify.sh
├── cases/
│   ├── 01-cannot-reach-database/
│   ├── 02-credentials-cannot-be-decrypted/
│   ├── 03-password-authentication-failed/
│   ├── 04-data-not-in-postgres/
│   ├── 05-port-already-allocated/
│   ├── bonus-a-webhook-url-wrong/          for fast finishers
│   └── bonus-b-third-service-unreachable/  for fast finishers
└── tools/
    └── teardown.sh            docker compose down -v across every stack here
```

Each case directory holds the same five files, so a group that finishes early can
pick up a bonus case with zero re-orientation:

```
setup.sh   SYMPTOM.md   compose.yaml   .env   verify.sh
```

Two more files per case land before the session: `HINT-1.txt` through `HINT-3.txt`,
and a password-protected `FIX.zip`. They are held back on purpose: a week of poking at
this with nothing but the logs is worth more than a week with the answers sitting in
the same directory.

(Case 02 and bonus-b each carry one extra directory the ticket needs: an attachment
the customer sent, and a second Compose project. You will find out why.)

---

*Session 1 (theory: images, layers, volumes, networks, the `localhost` trap) came
before this. Session 3 (queue mode, workers, webhooks, reverse proxies, scaling)
comes after, and the two bonus cases are its on-ramp.*
