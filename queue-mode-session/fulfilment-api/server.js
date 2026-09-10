// fulfilment-api: the downstream service the "Order intake" workflow calls.
//
// It does one thing badly on purpose: it can only work on CAPACITY requests at
// once. Each accepted request takes LATENCY_MS. Anything arriving while it is
// full gets HTTP 429 straight away. Adding n8n workers does not change either
// number, which is incident three in one sentence.
//
// No dependencies beyond Node's standard library.

const http = require('node:http');

const API_KEY = process.env.API_KEY || '';
const CAPACITY = Number(process.env.CAPACITY || 10);
const LATENCY_MS = Number(process.env.LATENCY_MS || 300);
const PORT = 8080;

const startedAt = new Date().toISOString();
let inFlight = 0;
let peakInFlight = 0;
let counters;
let events; // [timestampMs, statusCode, durationMs] for rate calculations
let recent; // last requests, newest first, for the console

function resetStats() {
	counters = { accepted: 0, rejected_429: 0, unauthorized_401: 0, by_mode: {} };
	events = [];
	recent = [];
	peakInFlight = inFlight;
}
resetStats();

function log(line) {
	process.stdout.write(`${new Date().toISOString()} ${line}\n`);
}

function record(status, durationMs, mode, order) {
	const now = Date.now();
	events.push([now, status, durationMs]);
	const cutoff = now - 5 * 60 * 1000;
	while (events.length && events[0][0] < cutoff) events.shift();
	recent.unshift({ at: new Date(now).toISOString(), status, duration_ms: durationMs, mode, order });
	if (recent.length > 25) recent.length = 25;
	const key = `${mode}:${status}`;
	counters.by_mode[key] = (counters.by_mode[key] || 0) + 1;
}

function rate(windowMs, predicate) {
	const cutoff = Date.now() - windowMs;
	let n = 0;
	for (const e of events) if (e[0] >= cutoff && predicate(e)) n++;
	return n / (windowMs / 1000);
}

function stats() {
	return {
		service: 'fulfilment-api',
		started_at: startedAt,
		capacity: CAPACITY,
		latency_ms: LATENCY_MS,
		in_flight: inFlight,
		peak_in_flight: peakInFlight,
		...counters,
		last_10s: {
			accepted_per_s: rate(10_000, (e) => e[1] === 200),
			rejected_per_s: rate(10_000, (e) => e[1] === 429),
		},
		recent,
	};
}

function send(res, status, body) {
	res.writeHead(status, { 'content-type': 'application/json' });
	res.end(JSON.stringify(body));
}

function readBody(req) {
	return new Promise((resolve) => {
		let raw = '';
		req.on('data', (c) => (raw += c));
		req.on('end', () => {
			try {
				resolve(JSON.parse(raw || '{}'));
			} catch {
				resolve({});
			}
		});
	});
}

const server = http.createServer(async (req, res) => {
	if (req.method === 'GET' && req.url === '/healthz') return send(res, 200, { status: 'ok' });
	if (req.method === 'GET' && req.url === '/stats') return send(res, 200, stats());
	if (req.method === 'POST' && req.url === '/stats/reset') {
		resetStats();
		log('stats reset');
		return send(res, 200, { reset: true });
	}

	if (req.method === 'POST' && req.url === '/orders') {
		const t0 = Date.now();
		const body = await readBody(req);
		const mode = String(body.mode || 'unknown');
		const order = String(body.order || '-');

		if (req.headers['x-api-key'] !== API_KEY) {
			counters.unauthorized_401++;
			record(401, 0, mode, order);
			log(`POST /orders 401 order=${order} mode=${mode} (missing or wrong X-Api-Key)`);
			return send(res, 401, { error: 'unauthorized' });
		}

		if (inFlight >= CAPACITY) {
			counters.rejected_429++;
			record(429, Date.now() - t0, mode, order);
			log(`POST /orders 429 order=${order} mode=${mode} in_flight=${inFlight}/${CAPACITY}`);
			return send(res, 429, { error: 'capacity exceeded', in_flight: inFlight, capacity: CAPACITY });
		}

		inFlight++;
		peakInFlight = Math.max(peakInFlight, inFlight);
		await new Promise((r) => setTimeout(r, LATENCY_MS));
		inFlight--;
		counters.accepted++;
		const took = Date.now() - t0;
		record(200, took, mode, order);
		log(`POST /orders 200 order=${order} mode=${mode} in_flight=${inFlight + 1}/${CAPACITY} ${took}ms`);
		return send(res, 200, { accepted: true, order });
	}

	send(res, 404, { error: 'not found' });
});

server.listen(PORT, () => {
	log(`fulfilment-api listening on :${PORT} capacity=${CAPACITY} latency_ms=${LATENCY_MS}`);
});

process.on('SIGTERM', () => server.close(() => process.exit(0)));
