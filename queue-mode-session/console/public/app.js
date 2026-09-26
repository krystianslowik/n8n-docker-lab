// Queue-mode lab page. No framework, no build step, no network calls except
// data/evidence.json (recorded rehearsal output shipped with the page) and,
// when you ask for it, your own lab's /api/state.

(() => {
	const NOTES_KEY = 'qmlab.notes.v1';
	const CHECKS_KEY = 'qmlab.checks.v1';
	const LIVE_KEY = 'qmlab.live.v1';
	const $ = (sel, root = document) => root.querySelector(sel);
	const $$ = (sel, root = document) => [...root.querySelectorAll(sel)];
	const esc = (s) => String(s ?? '').replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' })[c]);
	const load = (k) => { try { return JSON.parse(localStorage.getItem(k) || '{}'); } catch { return {}; } };
	const save = (k, v) => { try { localStorage.setItem(k, JSON.stringify(v)); } catch {} };

	// ---- lesson order and locking ----------------------------------------------
	// The five lessons run in order. A lesson opens once the previous lesson's box
	// is ticked, or its own box is (so unticking an earlier box never re-locks
	// finished work), or you chose "Open it anyway". Checklist, Stuck? and
	// Notebook are never locked. Overrides live under their own key so they never
	// show up as progress in the notebook export.
	const LESSONS = [
		{ route: 'start', check: 'start.done', name: 'Start' },
		{ route: 'trace', check: 'trace.done', name: 'Trace an order' },
		{ route: 'incident-1', check: 'inc1.done', name: 'Incident 1' },
		{ route: 'incident-2', check: 'inc2.done', name: 'Incident 2' },
		{ route: 'incident-3', check: 'inc3.done', name: 'Incident 3' },
	];
	const OPENED_KEY = 'qmlab.opened.v1';
	const opened = load(OPENED_KEY);
	// Returns the lesson that has to be finished first, or null when `route` is open.
	function blockedBy(route) {
		const i = LESSONS.findIndex((l) => l.route === route);
		if (i <= 0) return null;
		const prev = LESSONS[i - 1];
		return checks[prev.check] || checks[LESSONS[i].check] || opened[route] ? null : prev;
	}

	// ---- routing -------------------------------------------------------------
	const routes = $$('section.page').map((s) => s.dataset.route);
	const currentRoute = () => (routes.includes(location.hash.slice(1)) ? location.hash.slice(1) : 'start');

	// A locked lesson keeps its title readable and blurs the rest behind a card
	// that says what to finish first. The blurred part is inert, so keyboard and
	// screen-reader users can't land in it either.
	function applyGate(page) {
		const by = blockedBy(page.dataset.route);
		page.classList.toggle('locked', Boolean(by));
		let gate = $(':scope > .gate', page);
		if (by && !gate) {
			gate = document.createElement('div');
			gate.className = 'gate';
			(page.querySelector(':scope > .meta') || page.querySelector('h1')).after(gate);
		}
		if (gate) {
			gate.hidden = !by;
			if (by) {
				gate.innerHTML = `<p><span class="lock" aria-hidden="true"></span>Finish ${esc(by.name)} first, then tick the box at the end of it.</p>
					<div class="row"><a class="btn primary" href="#${by.route}">Go to ${esc(by.name)}</a><button class="btn quiet" type="button">Open it anyway</button></div>`;
				$('button', gate).addEventListener('click', () => {
					opened[page.dataset.route] = true;
					save(OPENED_KEY, opened);
					paintNav();
					applyGate(page);
				});
			}
		}
		[...page.children].forEach((el) => {
			if (!el.matches('h1, .meta, .gate')) el.inert = Boolean(by);
		});
	}

	function show(moveFocus) {
		const route = currentRoute();
		$$('section.page').forEach((s) => s.classList.toggle('active', s.dataset.route === route));
		$$('nav.lessons a').forEach((a) => {
			if (a.dataset.route === route) a.setAttribute('aria-current', 'page');
			else a.removeAttribute('aria-current');
		});
		if (route === 'notebook') renderNotebook();
		const page = $(`section.page[data-route="${route}"]`);
		applyGate(page);
		$(`nav.lessons a[data-route="${route}"]`)?.scrollIntoView({ block: 'nearest', inline: 'nearest' });
		document.title = `Queue-mode lab: ${page.querySelector("h1").textContent.trim()}`;
		window.scrollTo({ top: 0 });
		// Tell keyboard and screen-reader users the page changed.
		if (moveFocus) {
			const h1 = page.querySelector('h1');
			h1.setAttribute('tabindex', '-1');
			h1.focus({ preventScroll: true });
		}
	}
	window.addEventListener('hashchange', () => show(true));

	// ---- notes and checkboxes -------------------------------------------------
	const notes = load(NOTES_KEY);
	const checks = load(CHECKS_KEY);
	$$('[data-note]').forEach((el, i) => {
		const key = el.dataset.note;
		const label = el.closest('.prompt')?.querySelector('label');
		if (label) { el.id = el.id || `note-${i}`; label.htmlFor = el.id; }
		el.value = notes[key] || '';
		const status = document.createElement('div');
		status.className = 'saved';
		if (el.tagName === 'TEXTAREA') el.after(status);
		let timer;
		el.addEventListener('input', () => {
			notes[key] = el.value;
			clearTimeout(timer);
			timer = setTimeout(() => {
				save(NOTES_KEY, notes);
				status.textContent = 'Saved in this browser';
			}, 300);
		});
	});
	// Nav states: done (tick), current (underlined), open, or locked (lock glyph,
	// dimmed and slightly blurred). Locked items stay links: clicking one shows the
	// gate, which says why. A Next link that leads to a locked lesson says so too.
	function paintNav() {
		LESSONS.forEach((l) => {
			const a = $(`nav.lessons a[data-route="${l.route}"]`);
			const state = checks[l.check] ? 'done' : blockedBy(l.route) ? 'locked' : 'open';
			a.dataset.state = state;
			a.parentElement.dataset.state = state;
			$('.mark', a)?.remove();
			if (state === 'done') a.insertAdjacentHTML('beforeend', '<span class="mark done"><span aria-hidden="true">✓</span><span class="sr-only"> (done)</span></span>');
			if (state === 'locked') a.insertAdjacentHTML('afterbegin', '<span class="mark"><span class="lock" aria-hidden="true"></span><span class="sr-only">(locked) </span></span>');
		});
		$$('.pager a.next').forEach((a) => {
			const small = $('small', a);
			small.dataset.text ??= small.textContent;
			const by = blockedBy(a.getAttribute('href').slice(1));
			a.classList.toggle('locked', Boolean(by));
			small.textContent = by ? 'Next, once you tick the box above' : small.dataset.text;
		});
	}
	$$('[data-check]').forEach((el) => {
		el.checked = Boolean(checks[el.dataset.check]);
		el.addEventListener('change', () => {
			checks[el.dataset.check] = el.checked;
			save(CHECKS_KEY, checks);
			paintNav();
		});
	});

	// ---- notebook export ------------------------------------------------------
	function questionFor(el) {
		const label = el.closest('.prompt')?.querySelector('label');
		return label ? label.textContent.trim() : el.dataset.note;
	}
	function sectionTitle(el) {
		return el.closest('section.page')?.querySelector('h1')?.textContent.trim() || '';
	}
	function collect() {
		const out = [];
		$$('[data-note]').forEach((el) => {
			if (el.dataset.note.startsWith('meta.')) return;
			out.push({ section: sectionTitle(el), q: questionFor(el), a: notes[el.dataset.note] || '' });
		});
		return out;
	}
	function markdown() {
		const lines = [
			`# Queue-mode lab notes${notes['meta.name'] ? `: ${notes['meta.name']}` : ''}`,
			'',
			`Exported ${new Date().toISOString().slice(0, 16).replace('T', ' ')} UTC from ${location.host || 'a local file'}.`,
			notes['meta.env'] ? `Setup: ${notes['meta.env']}` : '',
			'',
			'## For the discussion',
			'',
			notes['meta.discussion'] || '_(not filled in)_',
			'',
			'## Progress',
			'',
			...[['start.done', 'Setup passed'], ['trace.done', 'Trace an order'], ['inc1.done', 'Incident 1'], ['inc2.done', 'Incident 2'], ['inc3.done', 'Incident 3 (optional)']]
				.map(([k, label]) => `- [${checks[k] ? 'x' : ' '}] ${label}`),
		];
		let current = '';
		for (const n of collect()) {
			if (n.section !== current) { lines.push('', `## ${n.section}`); current = n.section; }
			lines.push('', `**${n.q}**`, '', n.a.trim() || '_(no answer)_');
		}
		return lines.filter((l, i, a) => !(l === '' && a[i - 1] === '')).join('\n') + '\n';
	}
	function renderNotebook() {
		let current = '';
		const html = collect().map((n) => {
			const head = n.section !== current ? `<h2>${esc((current = n.section))}</h2>` : '';
			return `${head}<div class="note"><div class="q">${esc(n.q)}</div><div class="a ${n.a ? '' : 'empty'}">${esc(n.a || 'no answer yet')}</div></div>`;
		}).join('');
		$('#notes-list').innerHTML = html;
	}
	$('#export-md').addEventListener('click', () => {
		const blob = new Blob([markdown()], { type: 'text/markdown' });
		const a = document.createElement('a');
		const who = (notes['meta.name'] || 'notes').toLowerCase().replace(/[^a-z0-9]+/g, '-');
		a.href = URL.createObjectURL(blob);
		a.download = `qmlab-${who}.md`;
		a.click();
		URL.revokeObjectURL(a.href);
		$('#export-status').textContent = 'Downloaded.';
	});
	$('#copy-md').addEventListener('click', async () => {
		try { await navigator.clipboard.writeText(markdown()); $('#export-status').textContent = 'Copied to clipboard.'; }
		catch { $('#export-status').textContent = 'Clipboard blocked by the browser. Use Download instead.'; }
	});
	$('#clear-notes').addEventListener('click', () => {
		if (!confirm('Delete every note and checkbox on this page, in this browser? Export first if you want to keep them.')) return;
		localStorage.removeItem(NOTES_KEY); localStorage.removeItem(CHECKS_KEY); location.reload();
	});

	// ---- copy buttons ---------------------------------------------------------
	// Long commands scroll sideways with the scrollbar hidden. A fade on the right
	// edge says there's more, and goes away once you've scrolled to the end. The
	// observer re-measures when a command first becomes visible (page switch, a
	// hint opening) and when the window resizes.
	const markEdges = (block) => {
		block.classList.toggle('overflows', block.scrollWidth > block.clientWidth + 1);
		block.classList.toggle('at-end', block.scrollLeft + block.clientWidth >= block.scrollWidth - 1);
	};
	const sizes = new ResizeObserver((entries) => entries.forEach((e) => markEdges(e.target)));
	// The lesson nav and output boxes get the same fade when their end is cut off.
	function watchEdges(el) {
		sizes.observe(el);
		el.addEventListener('scroll', () => markEdges(el), { passive: true });
	}
	watchEdges($('nav.lessons'));
	$$('.evidence pre').forEach(watchEdges);
	$$('.cmd').forEach((block) => {
		sizes.observe(block);
		block.addEventListener('scroll', () => markEdges(block), { passive: true });
		const text = block.textContent;
		// The button lives on a wrapper that doesn't scroll, so it stays put when a
		// long command scrolls sideways. The wrapper takes the block's lab/hosted
		// visibility class with it.
		const wrap = document.createElement('div');
		wrap.className = 'cmd-wrap';
		['only-lab', 'only-hosted'].forEach((c) => block.classList.contains(c) && wrap.classList.add(c));
		block.before(wrap);
		wrap.appendChild(block);
		// Split the command into parts that explain themselves (commands.js).
		// The text stays the same, so selecting and copying still work.
		if (window.qmlabExplain) {
			block.innerHTML = window.qmlabExplain(text)
				.map((p) => (p.tip ? `<span class="tok" data-tip="${esc(p.tip)}">${esc(p.text)}</span>` : esc(p.text)))
				.join('');
			block.tabIndex = 0;
			block.setAttribute('aria-label', `${text.trim()}. Use the arrow keys to explain each part.`);
		}
		const btn = document.createElement('button');
		btn.className = 'copy'; btn.type = 'button'; btn.textContent = 'Copy';
		btn.setAttribute('aria-label', 'Copy command');
		btn.addEventListener('click', async () => {
			try { await navigator.clipboard.writeText(text); btn.textContent = 'Copied'; }
			catch { btn.textContent = 'Select and copy'; }
			setTimeout(() => (btn.textContent = 'Copy'), 1500);
		});
		wrap.appendChild(btn);
	});

	// ---- answers ask first --------------------------------------------------------
	// Opening an answer asks "Are you sure?" once, with a nudge that fits the page:
	// nothing written down yet, or a hint still closed. "Show me anyway" opens it
	// and doesn't ask again for that answer.
	$$('details.reveal').forEach((reveal) => {
		const summary = $('summary', reveal);
		summary.addEventListener('click', (e) => {
			if (reveal.open || reveal.dataset.confirmed) return;
			e.preventDefault();
			askBeforeReveal(reveal);
		});
	});
	function askBeforeReveal(reveal) {
		const page = reveal.closest('section.page');
		const wrote = $$('[data-note]', page).some((el) => (notes[el.dataset.note] || '').trim());
		const closedHint = $$('details.hint', page).some((h) => !h.open);
		const nudge = [
			wrote ? 'Try one more command first.' : "You haven't written anything down on this page yet.",
			closedHint ? "There's still a hint you haven't opened." : '',
		].filter(Boolean).join(' ');
		let box = reveal.nextElementSibling?.classList.contains('confirm') ? reveal.nextElementSibling : null;
		if (!box) {
			box = document.createElement('div');
			box.className = 'confirm';
			box.setAttribute('role', 'alertdialog');
			reveal.after(box);
		}
		const id = `confirm-${$$('details.reveal').indexOf(reveal)}`;
		box.setAttribute('aria-labelledby', id);
		box.innerHTML = `<p id="${id}"><strong>Are you sure?</strong> ${esc(nudge)}</p>
			<div class="row"><button class="btn primary" type="button">Keep trying</button><button class="btn quiet" type="button">Show me anyway</button></div>`;
		box.hidden = false;
		const [keep, show] = $$('button', box);
		const close = () => { box.hidden = true; $('summary', reveal).focus(); };
		keep.addEventListener('click', close);
		show.addEventListener('click', () => { reveal.dataset.confirmed = '1'; reveal.open = true; close(); });
		box.addEventListener('keydown', (e) => e.key === 'Escape' && close());
		keep.focus();
	}

	// ---- command explanations ---------------------------------------------------
	// One shared popover. Mouse: hover a part. Touch: tap it. Keyboard: Tab to a
	// command, then the arrow keys move from part to part.
	const tip = document.createElement('div');
	tip.id = 'tip';
	tip.setAttribute('role', 'tooltip');
	tip.setAttribute('aria-live', 'polite');
	tip.hidden = true;
	document.body.appendChild(tip);
	const TIPPED = '.tok, svg.diagram [data-tip]';
	let tipFor = null;
	function placeTip() {
		if (!tipFor) return;
		const r = tipFor.getBoundingClientRect();
		const box = tipFor.closest('.cmd, svg, pre').getBoundingClientRect();
		// Hide it if the part has scrolled out of its box or off the screen.
		if (r.right < box.left || r.left > box.right || r.bottom < 0 || r.top > innerHeight) return hideTip();
		const w = tip.offsetWidth, h = tip.offsetHeight;
		const above = r.top - h - 10 > 60;
		tip.style.top = `${above ? r.top - h - 8 : r.bottom + 8}px`;
		tip.style.left = `${Math.max(8, Math.min(r.left + r.width / 2 - w / 2, innerWidth - w - 8))}px`;
	}
	function showTip(tok) {
		tipFor?.classList.remove('on');
		tipFor = tok;
		tok.classList.add('on');
		const title = tok.dataset.tipTitle || tok.textContent;
		const cmd = tok.dataset.tipCmd ? `<code class="evidence-cmd">$ ${esc(tok.dataset.tipCmd)}</code>` : '';
		tip.innerHTML = `<code>${esc(title)}</code>${esc(tok.dataset.tip)}${cmd}`;
		tip.hidden = false;
		placeTip();
	}
	function hideTip() {
		tipFor?.classList.remove('on');
		tipFor = null;
		tip.hidden = true;
	}
	document.addEventListener('pointerover', (e) => {
		const tok = e.target.closest?.(TIPPED);
		if (tok && e.pointerType === 'mouse') showTip(tok);
	});
	document.addEventListener('pointerout', (e) => {
		if (e.pointerType === 'mouse' && e.target.closest?.(TIPPED) && !e.relatedTarget?.closest?.(TIPPED)) hideTip();
	});
	document.addEventListener('click', (e) => {
		const tok = e.target.closest(TIPPED);
		if (tok) showTip(tok);
		else hideTip();
	});
	document.addEventListener('scroll', placeTip, true);
	window.addEventListener('resize', hideTip);
	document.addEventListener('keydown', (e) => {
		if (e.key === 'Escape') return hideTip();
		const cmd = e.target.closest?.('.cmd, svg.diagram, .evidence pre');
		if (!cmd || (e.key !== 'ArrowRight' && e.key !== 'ArrowLeft')) return;
		const toks = $$(TIPPED, cmd).sort((a, b) => (a.dataset.order || 0) - (b.dataset.order || 0));
		if (!toks.length) return;
		e.preventDefault();
		const i = toks.indexOf(tipFor);
		const next = toks[i < 0 ? 0 : (i + (e.key === 'ArrowRight' ? 1 : toks.length - 1)) % toks.length];
		next.scrollIntoView({ block: 'nearest', inline: 'nearest' });
		showTip(next);
	});
	document.addEventListener('focusout', (e) => {
		if (e.target.closest?.('.cmd, svg.diagram, .evidence pre') && tipFor && e.target.contains(tipFor)) hideTip();
	});

	// ---- architecture diagram -------------------------------------------------
	const tpl = $('#diagram-tpl');
	$$('.diagram-slot').forEach((slot) => {
		slot.appendChild(tpl.content.cloneNode(true));
		// Arrows are thin, so each one gets a wide invisible copy to hover.
		$$('.link path', slot).forEach((path) => {
			const hit = path.cloneNode();
			hit.setAttribute('class', 'hit');
			path.before(hit);
		});
		const focus = (slot.dataset.focus || '').split(/\s+/).filter(Boolean);
		const map = { main: '.n-main', worker: '.n-worker', redis: '.n-redis', api: '.n-api', postgres: '.n-postgres' };
		focus.forEach((f) => $$(map[f], slot).forEach((n) => n.classList.add('focus')));
		if (!focus.length) $('.legend .l-focus', slot)?.remove();
	});

	// ---- recorded evidence ----------------------------------------------------
	fetch('data/evidence.json', { cache: 'no-cache' })
		.then((r) => (r.ok ? r.json() : Promise.reject(new Error(r.status))))
		.then(renderEvidence)
		.catch(() => $$('.evidence-slot').forEach((s) => (s.innerHTML = '<p class="small dim">Recorded evidence is not included in this copy of the page.</p>')));

	function renderEvidence(data) {
		const when = data.captured_at ? data.captured_at.replace('T', ' ').slice(0, 16) + ' UTC' : 'unknown time';
		$$('.evidence-slot').forEach((slot) => {
			const e = data.items?.[slot.dataset.evidence];
			if (!e) { slot.innerHTML = ''; return; }
			const title = slot.dataset.title || e.title;
			const label = `<span class="tag" title="Captured ${esc(when)}">Recorded</span>${esc(title)}`;
			// Commands and output both explain themselves on hover (commands.js).
			const html = (parts) => parts.map((p) => (p.tip ? `<span class="tok" data-tip="${esc(p.tip)}">${esc(p.text)}</span>` : esc(p.text))).join('');
			const cmdline = e.command ? `<span class="cmdline">$ ${window.qmlabExplain ? html(window.qmlabExplain(e.command)) : esc(e.command)}</span>\n` : '';
			const out = window.qmlabExplainOutput ? html(window.qmlabExplainOutput(e.output)) : esc(e.output);
			const pre = `<pre tabindex="0" aria-label="${esc(title)}. Use the arrow keys to explain each part.">${cmdline}${out}</pre>`;
			// In the reading flow, recorded output starts closed so it doesn't answer the
			// next step's prompt early. Inside a disclosure (the recorded-evidence box or
			// an answer) it's already opt-in, so it shows straight away.
			slot.innerHTML = slot.closest('details')
				? `<div class="evidence"><div class="label">${label}</div>${pre}</div>`
				: `<details class="evidence"><summary class="label">${label}</summary>${pre}</details>`;
			$$('pre', slot).forEach(watchEdges);
		});
		const m = data.metrics;
		if (m && $('#inc3-metrics')) {
			const rows = [
				['workers × effective concurrency', (r) => `${r.workers} × ${r.concurrency ?? '?'}`],
				['orders completed', (r) => `${r.success} / ${r.orders}`],
				['orders failed', (r) => r.error],
				['successful orders per second', (r) => r.success_per_s],
				['queue wait p50', (r) => `${r.wait_p50}s`],
				['execution duration p50', (r) => `${r.dur_p50}s`],
				['fulfilment-api refused (429)', (r) => r.api_429],
			];
			const cols = [['baseline', 'Baseline'], ['incident', "Customer's change"], ['remedy', 'Fix']].filter(([k]) => m[k]);
			$('#inc3-metrics').innerHTML = `<div class="evidence"><div class="label"><span class="tag" title="Captured ${esc(when)}">Recorded</span>The same 100-order load test in three configurations</div>
				<table><thead><tr><th scope="col">Measure</th>${cols.map(([, t]) => `<th scope="col" class="num">${t}</th>`).join('')}</tr></thead><tbody>
				${rows.map(([label, f]) => `<tr><td>${label}</td>${cols.map(([k]) => `<td class="num">${esc(f(m[k]))}</td>`).join('')}</tr>`).join('')}
				</tbody></table></div>`;
		}
	}

	// ---- live panel -----------------------------------------------------------
	const liveCfg = load(LIVE_KEY);
	// Your lab's console serves this page, normally on 5691 (CONSOLE_PORT). The
	// port is a first guess so the start page renders right away; the boot code
	// then confirms it by asking this page's own origin for api/state, which only
	// the lab answers. The hosted copy asks localhost:5691 instead, and only once
	// you open the panel. body.in-lab switches the start page between "run
	// setup.sh" (hosted) and "your lab is already running" (lab).
	let servedByLab = false;
	const labUrl = new URL('api/state', location.href).href;
	const hostedUrl = 'http://localhost:5691/api/state';
	const defaultUrl = () => (servedByLab ? labUrl : hostedUrl);
	function markLab(lab) {
		servedByLab = lab;
		document.body.classList.toggle('in-lab', lab);
		// If your lab is serving this page, setup.sh has run: count Start as done.
		if (lab && !checks['start.done']) {
			checks['start.done'] = true;
			save(CHECKS_KEY, checks);
			$$('[data-check="start.done"]').forEach((el) => (el.checked = true));
			paintNav();
			applyGate($(`section.page[data-route="${currentRoute()}"]`));
		}
	}
	markLab(location.port === '5691');
	const urlInput = $('#live-url');
	urlInput.value = liveCfg.url || defaultUrl();
	let timer = null;
	let failures = 0;

	function setPill(state, word) {
		$('#live-dot').className = state === 'on' ? 'dot on' : 'dot';
		$('#live-word').innerHTML = `Live<span class="long"> lab: ${esc(word)}</span>`;
	}
	function toggle(open) {
		document.body.classList.toggle('live-open', open);
		$('#live-toggle').setAttribute('aria-expanded', String(open));
		liveCfg.open = open; save(LIVE_KEY, liveCfg);
		clearInterval(timer);
		if (open) { poll(); timer = setInterval(poll, 3000); }
	}
	$('#live-toggle').addEventListener('click', () => toggle(!document.body.classList.contains('live-open')));
	$('#live-connect').addEventListener('click', () => {
		liveCfg.url = urlInput.value.trim() || defaultUrl(); save(LIVE_KEY, liveCfg); failures = 0; poll();
	});

	async function poll() {
		const url = urlInput.value.trim() || defaultUrl();
		try {
			const res = await fetch(url, { cache: 'no-store', signal: AbortSignal.timeout(2500) });
			if (!res.ok) throw new Error(`HTTP ${res.status}`);
			const s = await res.json();
			failures = 0;
			setPill('on', 'connected');
			renderLive(s);
		} catch (err) {
			failures++;
			setPill('off', 'not connected');
			$('#live-source').innerHTML = `Can't reach <code>${esc(url)}</code>.`;
			$('#live-body').innerHTML = `<p class="small dim">Start your lab with <code>./setup.sh</code> and open
				<a href="http://localhost:5691">localhost:5691</a>.${servedByLab ? '' : ' Some browsers block this hosted page from reading localhost.'}</p>`;
			if (failures > 3) { clearInterval(timer); timer = setInterval(poll, 15000); }
		}
	}

	// One renderer per source. Each gets that source's { ok, data, error } and
	// returns its block of the panel, so a failing source only blanks its own part.
	function unreachable(name, error) {
		return `<h3>${name}</h3><p class="st-error">unreachable: ${esc(error)}</p>`;
	}

	function renderRedis(r) {
		if (!r.ok) return unreachable('Redis', r.error);
		const d = r.data;
		const rows = d.dbs.map((db) => `<tr><td>db${db.db}</td><td class="num ${db.waiting ? 'st-new' : ''}">${db.waiting}</td><td class="num">${db.active}</td><td class="num">${db.keys}</td></tr>`).join('')
			|| '<tr><td colspan="4" class="dim">no keys in any database</td></tr>';
		const consumers = d.dbs.map((db) => {
			const who = d.consumers.filter((c) => c.db === db.db).map((c) => c.container);
			return `<li>db${db.db}: ${who.length ? esc(who.join(', ')) : '<span class="dim">nobody</span>'}</li>`;
		}).join('');
		return `<h3>Redis queue, per logical database</h3>
			<table><thead><tr><th>db</th><th class="num">waiting</th><th class="num">active</th><th class="num">keys</th></tr></thead><tbody>${rows}</tbody></table>
			${consumers ? `<h3>Waiting for jobs on each database</h3><ul class="plain">${consumers}</ul>` : ''}
			<p class="small dim">PING answers ${esc(d.ping)}. ${d.pubsub_channels.length} n8n pub/sub channels open.</p>`;
	}

	function renderExecutions(e) {
		if (!e.ok) return unreachable('Postgres', e.error);
		const l = e.data.last_60_s;
		const recent = e.data.recent.map((x) => {
			const wait = x.started_at ? ((new Date(x.started_at) - new Date(x.created_at)) / 1000).toFixed(2) + 's' : '–';
			return `<tr><td>${x.id}${x.retry_of ? ` <span class="dim">(retry of ${x.retry_of})</span>` : ''}</td><td>${esc(x.mode)}</td><td class="st-${esc(x.status)}">${esc(x.status)}</td><td class="num">${wait}</td></tr>`;
		}).join('');
		return `<h3>Executions in the last 60 seconds, from Postgres</h3>
			<table><tbody>
			<tr><td>succeeded / failed</td><td class="num"><span class="st-success">${l.success}</span> / <span class="st-error">${l.error}</span></td></tr>
			<tr><td>new or running</td><td class="num st-new">${l.in_progress}</td></tr>
			<tr><td>queue wait p50 / run p50</td><td class="num">${l.queue_wait_p50_s ?? '–'}s / ${l.run_p50_s ?? '–'}s</td></tr>
			<tr><td>still <code>new</code> after 30 s</td><td class="num ${e.data.new_older_than_30s ? 'st-error' : ''}">${e.data.new_older_than_30s}</td></tr>
			</tbody></table>
			<h3>Latest executions</h3>
			<table><thead><tr><th>id</th><th>mode</th><th>status</th><th class="num">wait</th></tr></thead><tbody>${recent}</tbody></table>`;
	}

	function renderFulfilment(f) {
		if (!f.ok) return unreachable('fulfilment-api', f.error);
		const d = f.data;
		const pct = Math.min(100, Math.round((d.in_flight / d.capacity) * 100));
		return `<h3>fulfilment-api, its own counters</h3>
			<div class="bar ${d.in_flight >= d.capacity ? 'full' : ''}"><div style="width:${pct}%"></div></div>
			<table><tbody>
			<tr><td>in flight now / capacity</td><td class="num">${d.in_flight} / ${d.capacity}</td></tr>
			<tr><td>peak in flight since reset</td><td class="num">${d.peak_in_flight}</td></tr>
			<tr><td>accepted / refused (429), last 10 s</td><td class="num">${d.last_10s.accepted_per_s.toFixed(1)}/s / ${d.last_10s.rejected_per_s.toFixed(1)}/s</td></tr>
			<tr><td>accepted / refused since reset</td><td class="num">${d.accepted} / ${d.rejected_429}</td></tr>
			</tbody></table>`;
	}

	function renderLive(s) {
		const t = new Date(s.captured_at).toLocaleTimeString();
		$('#live-source').innerHTML = `<span class="tag">Live</span>, updated ${esc(t)}`;
		$('#live-body').innerHTML = [
			renderRedis(s.redis),
			renderExecutions(s.executions),
			renderFulfilment(s.fulfilment),
		].join('');
	}

	// ---- boot -----------------------------------------------------------------
	paintNav();
	show(false);
	// The hosted copy only contacts localhost once you open the panel, so nobody
	// gets a browser permission prompt just for reading a lesson.
	if (liveCfg.open || servedByLab) toggle(true);
	fetch(labUrl, { cache: 'no-store' })
		.then((r) => (r.ok ? r.json() : null))
		.catch(() => null)
		.then((s) => {
			const lab = s?.source === 'live';
			if (lab === servedByLab) return;
			markLab(lab);
			if (!liveCfg.url) urlInput.value = defaultUrl();
			if (lab) toggle(true);
		});
})();
