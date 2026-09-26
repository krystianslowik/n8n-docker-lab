// What each part of each lab command does, for the hover explanations on
// command blocks. app.js calls qmlabExplain(line) and gets back one
// { text, tip } pair per token, whitespace included, so the command's text is
// unchanged. The explanations stay neutral: none of them names an incident's
// cause.
//
// A token is explained by where it sits, not only by what it is: the word after
// `docker compose logs` is a service name, and `-n` means different things to
// redis-cli and to grep. Keys are "<program>:<token>", with a few for service
// names ("service:<name>") and plain "<token>" for programs themselves.

(() => {
	const TIPS = {
		// programs and shell
		docker: 'The Docker command-line tool. It sends each request to your Docker engine.',
		'|': 'Pipe: the output of the command on the left becomes the input of the command on the right.',
		grep: 'Keeps only the lines that match the pattern after it.',
		curl: 'Sends an HTTP request from your terminal.',
		git: 'Git, for getting the lab repository.',
		cd: 'Changes into a directory.',
		'redis-cli': "Redis's command-line client. It ships in the Redis image and talks to the server in the same container.",

		// lab scripts
		'./setup.sh': 'Brings the lab up: pulls the images, imports the workflow and its credential on the first run, starts every service, then runs ./verify.sh.',
		'./verify.sh': 'Checks the baseline end to end: one production order through the queue, one manual test, and the fulfilment API receiving both.',
		'./reset.sh': 'Restores the known-good configuration and recreates Redis with an empty queue. Postgres data stays, so you can still look at what happened.',
		'./tools/evidence.sh': 'Read-only evidence. It prints every command it runs, so you can run them yourself next time.',
		'./tools/load-test.sh': 'Sends a burst of production orders, waits for them to finish, then reports outcomes from Postgres and from the fulfilment API.',
		'evidence.sh:executions': 'The last 12 executions from Postgres, with status, queue wait and run time.',
		'evidence.sh:config': 'The settings each running container actually got, with the encryption key shown as a short hash.',
		'evidence.sh:redis': 'PING, the databases that hold keys, queue lengths per database, which containers wait on which database, and the pub/sub channels.',
		'evidence.sh:downstream': "The fulfilment API's own counters and its last few log lines.",
		'evidence.sh:paths': "Which process ran what: main's Enqueued lines, the workers' started and finished lines, and main's OFFLOAD_MANUAL warning.",
		'psql:': 'evidence.sh runs one psql query against the execution_entity table here. The query is in tools/evidence.sh.',
		'load-test.sh:100': 'How many orders to send.',
		'load-test.sh:25': 'How many to send at the same time.',

		// docker compose
		'docker:compose': 'Docker Compose: acts on the services defined in compose.yaml in this directory (the qmlab project).',
		'compose:logs': "Prints a service's log output. Each line starts with the container name, which is how you tell the two workers apart.",
		'compose:ps': "Lists this project's containers with their state and health check result.",
		'compose:exec': "Runs a command inside the service's running container.",
		'compose:--since': 'Only log lines newer than the time that follows.',
		'compose:10m': 'Ten minutes.',
		'service:n8n-main': 'Service name from compose.yaml: n8n main, which serves the editor, receives webhooks and puts jobs on the queue.',
		'service:n8n-worker': 'Service name from compose.yaml: the workers. It covers both replicas, n8n-worker-1 and n8n-worker-2.',
		'service:redis': 'Service name from compose.yaml: Redis. The rest of the line runs inside its container.',
		'service:fulfilment-api': 'Service name from compose.yaml: the downstream API the workflow calls.',
		"compose:'table {{.Name}}\\t{{.Status}}\\t{{.Ports}}'": 'A Go template for the output: a table with only the name, status and ports columns.',
		'compose:--format': 'Picks which columns to print, with a Go template.',
		'compose:images': 'Lists the image each container runs: repository, tag and image ID.',
		'compose:config': 'Prints the configuration Compose would apply, with .env and the env files filled in. It shows what was intended; a running container may have been created from an older version.',
		'compose:top': "Lists the processes running inside each of the service's containers.",
		'compose:up': "Creates or updates the service's containers to match the configuration.",
		'compose:restart': 'Stops and starts the existing containers, without applying configuration changes.',
		'compose:-d': 'Detached: starts in the background and gives you the terminal back.',
		'compose:--scale': 'Sets how many containers a service runs.',
		'compose:n8n-worker=3': 'Three n8n-worker containers.',
		'compose:--index': 'Which replica to run in, when a service has several. Without it, exec picks the first one.',
		'compose:2': 'Replica 2, so the command runs in n8n-worker-2.',
		'compose:--tail': "Only the last few lines of each container's log.",
		'compose:5': 'Five lines.',
		'compose:--timestamps': 'Adds the time Docker received each line, in UTC.',
		'docker:inspect': "Prints a container's low-level details as JSON.",
		'docker:--format': 'Picks what to print with a Go template, instead of the whole JSON.',
		"docker:'{{.State.Health.Status}} {{json .Config.Healthcheck.Test}}'": "The template: the container's health status, then its health check command as JSON.",
		'docker:qmlab-n8n-worker-1': 'A container name: project qmlab, service n8n-worker, replica 1. Plain docker commands take container names; docker compose commands take service names.',
		'docker:stats': 'Live CPU, memory, network and disk use for each container.',
		'docker:--no-stream': 'Prints one snapshot and exits, instead of updating every second.',
		printenv: 'Prints environment variables. Given a name, it prints only that value.',
		'printenv:EXECUTIONS_MODE': 'The setting that decides how n8n runs executions. queue means main hands them to workers through Redis.',
		nslookup: 'Looks a name up in DNS, from inside the container.',
		'nslookup:redis': 'The name to look up: the Redis service.',
		nc: 'Netcat: opens a plain TCP connection.',
		'nc:-zv': '-z connects and closes without sending anything, and -v prints whether the port is open.',
		'nc:redis': 'The host to connect to: the Redis service, by name.',
		'nc:6379': "Redis's port.",
		'grep:EXECUTIONS_MODE': 'Keeps the lines that set EXECUTIONS_MODE.',
		';': 'Runs the next command once this one has finished.',
		'printenv:QUEUE_BULL_REDIS_DB': 'The Redis logical database n8n uses for its Bull queue. Unset means 0.',
		'redis-cli:1': 'Database 1.',
		'redis-cli:CLIENT': 'Commands about the connections to this Redis server.',
		'redis-cli:LIST': 'Lists every open connection, with the database each one selected and the command it last ran.',
		'redis-cli:PUBSUB': 'Commands about publish/subscribe.',
		'redis-cli:CHANNELS': 'Lists pub/sub channels that have at least one subscriber.',
		"redis-cli:'n8n*'": 'Only channels whose names start with n8n.',
		'grep:-A1': 'Also prints the line after each match.',
		'grep:-E': 'Treats the pattern as an extended regular expression, so | means or.',
		'grep:-iE': 'Ignores case, and treats the pattern as an extended regular expression.',
		"grep:'Enqueued execution'": 'The line main logs each time it puts an execution on the queue.',
		"grep:'Concurrency:'": 'The line each worker prints at startup with the concurrency it uses.',
		"grep:'could not be decrypted'": 'Part of the error n8n logs when it can\'t decrypt a stored credential.',
		"grep:'Worker (started|finished) execution|could not be decrypted'": 'Worker start and finish lines, plus credential decryption errors.',
		"grep:'crashed|queue recovery'": "Main's lines about crashed executions and its queue recovery check.",
		'grep:Mismatching': 'The start of the error main logs when its encryption keys disagree.',
		'curl:http://localhost:5692/stats': "The fulfilment API's own counters, on its published port.",
		"compose:'table {{.Name}}\\t{{.Status}}'": 'A Go template for the output: a table with only the name and status columns.',

		// redis-cli
		'redis-cli:-n': 'Picks a logical database. One Redis server has 16, numbered 0 to 15, and 0 is the default.',
		'redis-cli:0': 'Database 0.',
		'redis-cli:ping': "Asks the server to reply PONG. That proves it's up and answering, and says nothing about what's stored in it.",
		'redis-cli:INFO': 'Server information. The word after it picks one section.',
		'redis-cli:keyspace': 'The section that lists every database holding keys, with how many keys each has.',
		'redis-cli:LLEN': 'The length of a list. Bull keeps jobs that are waiting for a worker in a list.',
		'redis-cli:bull:jobs:wait': "Bull's list of waiting jobs: key prefix bull, queue name jobs, list wait.",

		// grep
		'grep:-m1': 'Stops after the first matching line.',
		'grep:-B2': 'Also prints the 2 lines before each match.',
		'grep:-A2': 'Also prints the 2 lines after each match.',
		'grep:-c': 'Prints how many lines matched instead of the lines.',
		'grep:"Enqueued execution"': 'The line main logs each time it puts an execution on the queue.',
		'grep:"Worker started execution"': 'The line a worker logs when it takes a job off the queue.',
		'grep:"Worker started"': 'The start of the line a worker logs when it takes a job off the queue.',
		'grep:OFFLOAD_MANUAL': "Matches the line in main's log that mentions OFFLOAD_MANUAL_EXECUTIONS_TO_WORKERS.",
		'grep:"Concurrency:"': 'The line each worker prints at startup with the concurrency it uses.',
		'grep:" 429 "': "Matches fulfilment-api's log lines for refused requests. The spaces stop it matching 429 inside another number.",

		// curl
		'curl:-s': 'Silent: no progress meter.',
		'curl:-X': 'Sets the HTTP method.',
		'curl:POST': 'POST, the method the shop uses to send an order.',
		'curl:localhost:5690/webhook/orders': "n8n main's published port, 5690, and the Order intake workflow's webhook path.",
		'curl:-H': 'Adds a request header.',
		"curl:'content-type: application/json'": 'Tells n8n the body is JSON.',
		'curl:-d': 'The request body.',
		'curl:\'{"order":"TRACE-1"}\'': 'The order. The workflow passes the order reference on to the fulfilment API.',

		// git and cd
		'git:clone': 'Downloads a copy of the repository.',
		'git:https://github.com/krystianslowik/n8n-docker-lab.git': 'The lab repository.',
		'cd:n8n-docker-lab/queue-mode-session': "The lab's directory. Run every command in this lab from here.",
	};

	const INCIDENT_VERIFY = {
		1: 'Checks incident 1 by outcome: a new production order and a new manual test both have to succeed.',
		2: 'Checks incident 2 by outcome: a new order has to complete, and each of the five orders from the incident has to have succeeded or been retried.',
		3: 'Checks incident 3 by outcome: the load test has to complete 100 of 100 orders with at most 5 refused by the fulfilment API.',
	};

	// Compose subcommands whose first plain word is a service name, and options
	// whose next word is their value (so `--index 2` isn't read as a service).
	const SERVICE_SUBS = ['logs', 'exec', 'config', 'top', 'up', 'restart', 'ps'];
	const VALUE_OPTIONS = ['--index', '--tail', '--since', '--scale', '--format'];

	// The program a token starts, for looking up the tokens after it.
	function programOf(token) {
		if (token.startsWith('./')) return token.split('/').pop();
		return token;
	}

	function tipForProgram(token) {
		const incident = token.match(/^\.\/incidents\/0(\d)-[^/]+\/(setup|verify)\.sh$/);
		if (incident) {
			const n = Number(incident[1]);
			return incident[2] === 'setup'
				? `Sets up incident ${n}: changes the lab the way the customer did and replays their traffic. Don't read the script; it contains the answer.`
				: INCIDENT_VERIFY[n];
		}
		return TIPS[token];
	}

	// One line of a command, as [{ text, tip }] with whitespace kept as tip-less parts.
	function explainLine(line) {
		const parts = [];
		const re = /'[^']*'|"[^"]*"|[|;]|[^\s|;]+/g;
		let last = 0;
		let prog = null; // the program the current token belongs to
		let sub = null; // docker compose subcommand
		let service = null; // service named after a subcommand such as `logs` or `exec`
		let valueNext = false; // the previous token was an option that takes a value
		for (const m of line.matchAll(re)) {
			if (m.index > last) parts.push({ text: line.slice(last, m.index) });
			last = m.index + m[0].length;
			const t = m[0];
			let tip;
			if (t === '|' || t === ';') {
				tip = TIPS[t];
				prog = sub = service = null;
			} else if (!prog) {
				tip = tipForProgram(t);
				prog = programOf(t);
			} else if (prog === 'docker' && t === 'compose') {
				tip = TIPS['docker:compose'];
				prog = 'compose';
			} else if (prog === 'compose' && !sub && TIPS[`compose:${t}`] && !t.startsWith('-')) {
				tip = TIPS[`compose:${t}`];
				sub = t;
			} else if (prog === 'compose' && SERVICE_SUBS.includes(sub) && !service && !valueNext && !t.startsWith('-')) {
				tip = TIPS[`service:${t}`];
				service = t;
				// After `exec <service>` comes the command that runs inside it.
				if (sub === 'exec') prog = null;
			} else {
				tip = TIPS[`${prog}:${t}`];
			}
			valueNext = VALUE_OPTIONS.includes(t);
			parts.push({ text: t, tip });
		}
		if (last < line.length) parts.push({ text: line.slice(last) });
		return parts;
	}

	// ---- output --------------------------------------------------------------
	// Recorded evidence mixes commands ($ lines) with their output. Each rule is
	// [pattern, explanation, only-on-lines-matching]; the explanation can use the
	// match. Earlier rules win where two overlap.
	const HEADERS = {
		id: 'The execution ID. Logs and the editor use the same number.',
		mode: 'How it started: webhook is a production order, manual is the Execute button, retry is Retry in the Executions list.',
		status: 'The execution status in Postgres.',
		created: 'When main created the record, in UTC.',
		queue_wait_s: 'Seconds from created to started: time spent waiting for a worker. Empty if it never started.',
		run_s: 'Seconds from started to stopped: time spent running.',
		retry_of: 'For a retry, the execution it retried.',
		container: 'The running container.',
		REDIS_DB: 'QUEUE_BULL_REDIS_DB inside the container: the Redis logical database for the queue.',
		PREFIX: 'QUEUE_BULL_PREFIX inside the container: the start of every queue key. bull is the default.',
		KEY_SHA256: 'The first 12 characters of a SHA-256 hash of N8N_ENCRYPTION_KEY. Equal hashes mean equal keys, and the key itself stays hidden.',
		CONC_LIMIT: 'N8N_CONCURRENCY_PRODUCTION_LIMIT inside the container.',
		command: "The container's command line.",
	};
	const MODES = {
		webhook: 'A production order: the shop called the webhook.',
		manual: "A manual test from the editor's Execute button.",
		retry: "A retry, started from the editor's Executions list. retry_of names the original.",
	};
	const STATUSES = {
		success: 'It finished, and every node succeeded.',
		error: 'It ran and failed.',
		new: 'Main created the record, and no worker has started it.',
		crashed: "n8n marked it as lost. Main's queue recovery does this to executions that have no job in its queue.",
	};
	const STATS = {
		started_at: 'When the API process started.',
		capacity: 'How many requests it works on at once.',
		latency_ms: 'How long each accepted request takes.',
		in_flight: 'Requests in progress right now.',
		peak_in_flight: 'The most requests in progress at once since the counters were reset.',
		accepted: 'Requests it accepted with HTTP 200.',
		rejected_429: 'Requests it refused with HTTP 429 because it was full.',
		unauthorized_401: 'Requests with a missing or wrong API key.',
		by_mode: 'The same counts, split by execution mode and status code.',
		last_10s: 'Accept and refuse rates over the last 10 seconds.',
	};
	const LOAD = {
		'executions succeeded': 'Executions that ended with status success in Postgres.',
		'executions failed (error)': 'Executions that ran and failed.',
		'executions crashed / still pending': 'Executions n8n gave up on, and ones that never finished before the script stopped waiting.',
		'first enqueue to last finish': 'Wall-clock time from the first order being created to the last one finishing.',
		'successful orders per second': 'Useful throughput: successes divided by that time.',
		'queue wait p50 / p95': 'Time waiting for a worker: the median, and the time 95% of orders came in under.',
		'execution duration p50 / p95': 'Time spent running once a worker had it: the median, and the time 95% of runs came in under.',
		'fulfilment-api accepted (200)': 'Requests the API accepted, from its own counters.',
		'fulfilment-api refused (429)': 'Requests the API refused because it was full. Each retry counts again.',
		'fulfilment-api peak in flight': 'The most requests the API worked on at once, against its capacity.',
	};
	const n = (m, i) => m[0].match(/\d+/g)[i];
	const OUTPUT_RULES = [
		[/✓/g, 'This check passed.'],
		[/✗/g, 'This check failed.'],
		[/^\s*·/g, 'A note from the script, not a check.'],
		[/\bPASS:/g, 'Every check above passed.'],
		[/\bFAIL:/g, 'At least one check above failed.'],
		[/\brunning\/healthy\b/g, 'From docker compose ps: running, and the health check passes.'],
		[/\(healthy\)/g, 'The health check passes. For n8n, that means it can reach Postgres and Redis.'],
		[/manual offloading is off/g, "OFFLOAD_MANUAL_EXECUTIONS_TO_WORKERS isn't true, so main runs manual executions itself."],
		[/'Worker started execution \d+'/g, "verify.sh found this line in a worker's log, which proves the queue delivered the job."],
		[/\bexecution \d+(?: finished:)? (?:success|error|new|crashed)\b/g, (m) => `Execution ${n(m, 0)}'s final status, read from Postgres.`],
		[/fulfilment-api received a (?:production|manual \(test\)) request/g, "The API's own log has a request with that mode."],
		[/Enqueued execution \d+ \(job \d+\)/g, (m) => `Main put execution ${n(m, 0)} on the queue as job ${n(m, 1)}. Job numbers count up per queue.`],
		[/Worker started execution \d+ \(job \d+\)/g, (m) => `This worker took job ${n(m, 1)} off the queue and started execution ${n(m, 0)}.`],
		[/Worker finished execution \d+ \(job \d+\)/g, (m) => `The worker is done with execution ${n(m, 0)}. Finished includes failed runs; the status is in Postgres.`],
		[/\bn8n-(?:worker|main)-\d+\b(?=\s+(?:\||Concurrency))/g, 'The container that wrote this line.'],
		[/Concurrency: \d+/g, (m) => `The concurrency this worker reports at startup: up to ${n(m, 0)} executions at once.`],
		[/Credentials could not be decrypted\..*/g, 'The worker couldn\'t decrypt a stored credential with the encryption key it was given.'],
		[/error:\w+:Provider routines::bad decrypt/g, 'The underlying OpenSSL error behind the line above.'],
		[/Discovered \d+ cluster checks/g, "A worker startup message. It isn't about any execution."],
		[/OFFLOAD_MANUAL_EXECUTIONS_TO_WORKERS -> .*/g, "Main's deprecation warning at startup. It says where manual executions run while this setting is off."],
		[/Restarting \(\d+\) .*ago/g, 'Docker keeps restarting main because the process exits. The number in brackets is its exit code.'],
		[/Error: Mismatching encryption keys\..*/g, 'Main compares N8N_ENCRYPTION_KEY with the key it saved in its volume on first boot. They differ, so it refuses to start.'],
		[/Last session crashed/g, 'Main found that its previous run ended without a clean shutdown: the crash journal it keeps while running was still there.'],
		[/Marked executions as `crashed`/g, 'n8n logs this each time it sets executions to crashed. The queue recovery check on the next line does that before it logs.'],
		[/Completed queue recovery check, recovered dangling executions/g, "Main's queue recovery: executions that are new in Postgres but have no job in its queue get marked crashed."],
		[/^PONG$/g, 'The Redis server answered.'],
		[/^# Keyspace$/g, 'One line per logical database that holds keys. Empty databases are left out.'],
		[/^db\d+:keys=\d+.*$/g, (m) => `Database ${n(m, 0)} holds ${n(m, 1)} keys. expires counts keys with a time to live, and avg_ttl is their average in milliseconds.`],
		[/\bdb\d+ {2}waiting=\d+ {2}active=\d+/g, (m) => `Bull's queue in database ${n(m, 0)}: ${n(m, 1)} jobs waiting for a worker, ${n(m, 2)} being worked on.`],
		[/n8n-worker-\d+ is waiting for jobs on db\d+/g, (m) => `From CLIENT LIST: this worker has a blocking read open on database ${n(m, 2)}'s queue.`],
		[/^n8n:n8n\.[\w-]+$/g, 'An n8n pub/sub channel. Channels belong to the whole Redis server, whatever the database number.'],
		[/\((?:source|the container's)[^)]*\)/g, "Where this section's data comes from."],
		[/\b(?:id|mode|status|created|queue_wait_s|run_s|retry_of)\b/g, (m) => HEADERS[m[0]], (line) => line.includes('queue_wait_s')],
		[/(?<=\|\s)(?:webhook|manual|retry)\b/g, (m) => MODES[m[0]]],
		[/(?<=\|\s)(?:success|error|new|crashed)\b/g, (m) => STATUSES[m[0]]],
		[/\b(?:container|REDIS_DB|PREFIX|KEY_SHA256|CONC_LIMIT|command)\b/g, (m) => HEADERS[m[0]], (line) => line.includes('KEY_SHA256')],
		[/\bstart \(image default\)/g, "Main runs the image's default command, which starts n8n main."],
		[/\bworker --concurrency=\d+/g, 'Started as a worker. --concurrency is the flag it was given.'],
		[/\b[0-9a-f]{12}\b/g, 'The key hash. Compare it across the rows.', (line) => /n8n-(?:main|worker)-\d/.test(line)],
		[/\bunset\b/g, 'Not set in this container.', (line) => /n8n-(?:main|worker)-\d/.test(line)],
		[/(?<=\s)bull(?=\s)/g, 'The queue key prefix. bull is the default.', (line) => /n8n-(?:main|worker)-\d/.test(line)],
		[/"(?:started_at|capacity|latency_ms|in_flight|peak_in_flight|accepted|rejected_429|unauthorized_401|by_mode|last_10s)"/g, (m) => STATS[m[0].slice(1, -1)]],
		[/POST \/orders (?:200|429|401)/g, (m) => ({ 200: 'An order the API accepted.', 429: 'An order the API refused because it was full.', 401: 'A request with a missing or wrong API key.' })[m[0].slice(-3)]],
		[/order=[\w-]+/g, "The order reference from the shop's request."],
		[/mode=\w+/g, 'The execution mode the workflow sent: production for webhook orders, test for manual runs.'],
		[/in_flight=\d+\/\d+/g, 'Requests in progress when this one finished, out of the capacity.'],
		[/\b\d+ms$/g, 'How long the API took to answer.'],
		[/webhook answered 200 for \d+\/\d+ requests/g, 'Every webhook call was accepted. The results below say what happened after that.'],
		[new RegExp(Object.keys(LOAD).map((k) => k.replace(/[()/]/g, '\\$&')).join('|'), 'g'), (m) => LOAD[m[0]]],
		[/^RESULT .*/g, 'The same numbers on one line, for scripts and your notes.'],
		[/^Load test L\d+:.*/g, "The run's ID, how many orders it sent and how many at once, and how many worker containers there were."],
	];

	function explainOutputLine(line) {
		// A command inside the output: explain it like a command box, but not
		// the comment after it.
		if (line.startsWith('$ psql:')) return [{ text: '$ ' }, { text: line.slice(2), tip: TIPS['psql:'] }];
		if (line.startsWith('$ ')) {
			const cut = line.search(/\s{2,}(?:#|\()/);
			const cmd = cut < 0 ? line.slice(2) : line.slice(2, cut);
			return [{ text: '$ ' }, ...explainLine(cmd), ...(cut < 0 ? [] : [{ text: line.slice(cut) }])];
		}
		const taken = [];
		for (const [re, tip, only] of OUTPUT_RULES) {
			if (only && !only(line)) continue;
			for (const m of line.matchAll(re)) {
				const start = m.index, end = start + m[0].length;
				if (!m[0] || taken.some((t) => start < t.end && end > t.start)) continue;
				const text = typeof tip === 'function' ? tip(m) : tip;
				if (text) taken.push({ start, end, tip: text });
			}
		}
		taken.sort((a, b) => a.start - b.start);
		const parts = [];
		let last = 0;
		for (const t of taken) {
			if (t.start > last) parts.push({ text: line.slice(last, t.start) });
			parts.push({ text: line.slice(t.start, t.end), tip: t.tip });
			last = t.end;
		}
		if (last < line.length) parts.push({ text: line.slice(last) });
		return parts;
	}

	window.qmlabExplainOutput = (text) =>
		text.split('\n').flatMap((line, i) => (i ? [{ text: '\n' }, ...explainOutputLine(line)] : explainOutputLine(line)));

	window.qmlabExplain = (text) =>
		text.split('\n').flatMap((line, i) => (i ? [{ text: '\n' }, ...explainLine(line)] : explainLine(line)));
})();
