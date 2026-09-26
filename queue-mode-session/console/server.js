// Incident console server.
//
// Serves the lesson page (console/public) and the pixel art (assets/), plus one
// read-only endpoint, GET /api/state, that reports what the deployment is doing
// right now: Redis queue lengths per logical database, which connections are
// waiting for jobs on which database, execution records from Postgres, and the
// fulfilment API's own counters.
//
// It runs on the n8n image and borrows that image's copies of `pg` and
// `ioredis`, so the lab needs no npm install. That ties it to the pinned image
// (2.33.0), which is fine for a lab and would not be fine anywhere else.
//
// It reads Docker nothing. Container state belongs in your terminal.

const http = require('node:http');
const fs = require('node:fs');
const path = require('node:path');
const dns = require('node:dns').promises;
const { createRequire } = require('node:module');

const n8nRequire = createRequire('/usr/local/lib/node_modules/n8n/package.json');
const { Pool } = n8nRequire('pg');
const Redis = n8nRequire('ioredis');

const PORT = 8080;
const PUBLIC_DIR = path.join(__dirname, 'public');
const ASSETS_DIR = '/srv/assets';
const REDIS_HOST = process.env.REDIS_HOST || 'redis';
const FULFILMENT_URL = process.env.FULFILMENT_URL || 'http://fulfilment-api:8080';
const QUEUE = 'bull:jobs';

const pool = new Pool({ max: 3, connectionTimeoutMillis: 2000 });
pool.on('error', () => {});

const redisClients = new Map();
function redisFor(db) {
	if (!redisClients.has(db)) {
		const client = new Redis({
			host: REDIS_HOST,
			db,
			lazyConnect: false,
			maxRetriesPerRequest: 1,
			connectTimeout: 2000,
			connectionName: `qmlab-console-db${db}`,
		});
		client.on('error', () => {});
		redisClients.set(db, client);
	}
	return redisClients.get(db);
}

const nameCache = new Map();
async function containerName(ip) {
	if (nameCache.has(ip)) return nameCache.get(ip);
	let name = ip;
	try {
		// Docker's embedded DNS answers reverse lookups with "<container>.<network>".
		const [host] = await dns.reverse(ip);
		if (host) name = host.split('.')[0].replace(/^qmlab-/, '');
	} catch {}
	nameCache.set(ip, name);
	return name;
}

async function redisState() {
	const base = redisFor(0);
	const ping = await base.ping();
	const keyspace = await base.info('keyspace');
	const dbs = [...keyspace.matchAll(/^db(\d+):keys=(\d+)/gm)].map((m) => ({
		db: Number(m[1]),
		keys: Number(m[2]),
	}));
	for (const entry of dbs) {
		const r = redisFor(entry.db);
		const [waiting, active, delayed, failed, completed] = await Promise.all([
			r.llen(`${QUEUE}:wait`),
			r.llen(`${QUEUE}:active`),
			r.zcard(`${QUEUE}:delayed`),
			r.zcard(`${QUEUE}:failed`),
			r.zcard(`${QUEUE}:completed`),
		]);
		Object.assign(entry, { waiting, active, delayed, failed, completed });
	}

	// Bull workers block on BRPOPLPUSH against the database they selected.
	const clients = (await base.client('LIST'))
		.split('\n')
		.filter((line) => line.includes('cmd=brpoplpush'))
		.map((line) => ({
			ip: (line.match(/ addr=([\d.]+):/) || [])[1],
			db: Number((line.match(/ db=(\d+)/) || [])[1]),
		}));
	const consumers = await Promise.all(
		clients.map(async (c) => ({ container: await containerName(c.ip), db: c.db })),
	);
	consumers.sort((a, b) => a.container.localeCompare(b.container));

	const channels = await base.pubsub('CHANNELS', 'n8n*');
	return { ping, dbs, consumers, pubsub_channels: channels.sort() };
}

async function executionState() {
	const q = (sql) => pool.query(sql).then((r) => r.rows);
	const [byStatus, recent, lastMinute] = await Promise.all([
		q(`SELECT status, mode, COUNT(*)::int AS n FROM execution_entity
		   WHERE "createdAt" > now() - interval '15 minutes' GROUP BY 1, 2 ORDER BY 1, 2`),
		q(`SELECT id, mode, status, "createdAt" AS created_at, "startedAt" AS started_at,
		          "stoppedAt" AS stopped_at, "retryOf" AS retry_of
		   FROM execution_entity ORDER BY id DESC LIMIT 12`),
		q(`SELECT COUNT(*) FILTER (WHERE status = 'success')::int AS success,
		          COUNT(*) FILTER (WHERE status = 'error')::int AS error,
		          COUNT(*) FILTER (WHERE status IN ('new', 'running'))::int AS in_progress,
		          ROUND(EXTRACT(EPOCH FROM PERCENTILE_CONT(0.5) WITHIN GROUP
		            (ORDER BY "startedAt" - "createdAt"))::numeric, 2)::float AS queue_wait_p50_s,
		          ROUND(EXTRACT(EPOCH FROM PERCENTILE_CONT(0.5) WITHIN GROUP
		            (ORDER BY "stoppedAt" - "startedAt"))::numeric, 2)::float AS run_p50_s
		   FROM execution_entity WHERE "createdAt" > now() - interval '60 seconds'`),
	]);
	const stuck = await q(`SELECT COUNT(*)::int AS n FROM execution_entity
	                       WHERE status = 'new' AND "createdAt" < now() - interval '30 seconds'`);
	return { last_15_min: byStatus, recent, last_60_s: lastMinute[0], new_older_than_30s: stuck[0].n };
}

async function fulfilmentState() {
	const res = await fetch(`${FULFILMENT_URL}/stats`, { signal: AbortSignal.timeout(2000) });
	const s = await res.json();
	s.recent = s.recent.slice(0, 8);
	return s;
}

async function settle(fn) {
	try {
		return { ok: true, data: await fn() };
	} catch (error) {
		return { ok: false, error: String(error.message || error) };
	}
}

async function state() {
	const [redis, executions, fulfilment] = await Promise.all([
		settle(redisState),
		settle(executionState),
		settle(fulfilmentState),
	]);
	return { source: 'live', captured_at: new Date().toISOString(), redis, executions, fulfilment };
}

const TYPES = {
	'.html': 'text/html; charset=utf-8',
	'.js': 'text/javascript; charset=utf-8',
	'.css': 'text/css; charset=utf-8',
	'.json': 'application/json; charset=utf-8',
	'.png': 'image/png',
	'.svg': 'image/svg+xml',
	'.md': 'text/markdown; charset=utf-8',
};

function serveFile(res, root, rel) {
	const file = path.normalize(path.join(root, rel));
	if (!file.startsWith(root)) return notFound(res);
	fs.stat(file, (err, st) => {
		if (err || !st.isFile()) return notFound(res);
		res.writeHead(200, {
			'content-type': TYPES[path.extname(file)] || 'application/octet-stream',
			'cache-control': 'no-cache',
		});
		fs.createReadStream(file).pipe(res);
	});
}

function notFound(res) {
	res.writeHead(404, { 'content-type': 'text/plain' });
	res.end('not found');
}

// The hosted copy of this page may ask a participant's local lab for live
// state. The endpoint is read-only, so it answers any origin, including the
// private-network preflight Chromium sends before a public page reads localhost.
function cors(res) {
	res.setHeader('access-control-allow-origin', '*');
	res.setHeader('access-control-allow-methods', 'GET, OPTIONS');
	res.setHeader('access-control-allow-headers', '*');
	res.setHeader('access-control-allow-private-network', 'true');
}

http
	.createServer(async (req, res) => {
		const url = new URL(req.url, 'http://console');
		if (url.pathname.startsWith('/api/')) {
			cors(res);
			if (req.method === 'OPTIONS') return res.writeHead(204).end();
			if (url.pathname === '/api/state') {
				const body = JSON.stringify(await state());
				res.writeHead(200, { 'content-type': 'application/json', 'cache-control': 'no-store' });
				return res.end(body);
			}
			return notFound(res);
		}
		if (url.pathname.startsWith('/assets/')) {
			return serveFile(res, ASSETS_DIR, url.pathname.slice('/assets/'.length));
		}
		const rel = url.pathname === '/' ? 'index.html' : url.pathname.slice(1);
		return serveFile(res, PUBLIC_DIR, rel);
	})
	.listen(PORT, () => {
		process.stdout.write(`incident console on :${PORT}\n`);
	});
