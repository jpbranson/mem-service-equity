// Memphis Service Equity front end. It reads only the files written by
// site/build_site_data.R and never computes a statistic (plan section 8, D16):
// it looks values up, formats them and compares intervals for overlap.
(() => {
  'use strict';

  const DATA = 'data/';
  const PANEL_ORDER = ['mata', 'mlgw', '311', 'food-safety', 'permits'];
  const VARIANT_LABELS = {
    lower_bound: 'Deadline at the low end of the target range',
    window_14d: 'Re-reported within 14 days',
    window_60d: 'Re-reported within 60 days',
    radius_25m: 'Same location within 25 m',
    radius_100m: 'Same location within 100 m',
  };

  const state = { manifest: null, cols: {}, areas: {}, demo: null, hex: new Map(), points: new Map(), fresh: true };

  // ---- small helpers ---------------------------------------------------------

  const $ = (sel) => document.querySelector(sel);

  // Builds DOM nodes. Strings become text nodes, so data is never parsed as HTML.
  function el(tag, attrs, ...kids) {
    const node = document.createElement(tag);
    for (const [k, v] of Object.entries(attrs || {})) {
      if (v == null || v === false) continue;
      if (k === 'class') node.className = v;
      else if (k === 'style') Object.assign(node.style, v);
      else if (k.startsWith('on')) node.addEventListener(k.slice(2), v);
      else node.setAttribute(k, v === true ? '' : v);
    }
    for (const kid of kids.flat()) {
      if (kid == null || kid === false) continue;
      node.append(kid instanceof Node ? kid : String(kid));
    }
    return node;
  }

  async function getJSON(path) {
    const res = await fetch(DATA + path, { cache: 'no-cache' });
    if (res.status === 404) return null;
    if (!res.ok) throw new Error(`${path}: HTTP ${res.status}`);
    return res.json();
  }

  const todayChicago = () =>
    new Intl.DateTimeFormat('en-CA', { timeZone: 'America/Chicago' }).format(new Date());
  const daysBetween = (a, b) => Math.round((Date.parse(b) - Date.parse(a)) / 86400000);
  const fmtDate = (iso) => iso
    ? new Date(iso + 'T12:00:00').toLocaleDateString('en-US', { month: 'short', day: 'numeric', year: 'numeric' })
    : '';
  const typeLabel = (t) => t.replace(/^[^-]*-/, '');

  // A metrics row (array) as an object keyed by the manifest's column names.
  const asRow = (r) => Object.fromEntries(Object.entries(state.cols).map(([c, i]) => [c, r[i]]));

  // ---- formatting ------------------------------------------------------------

  function fmtValue(unit, v) {
    if (v == null) return '';
    if (unit === 'proportion') return `${(v * 100).toFixed(1)}%`;
    if (unit === 'business_days') return `${v} business day${v === 1 ? '' : 's'}`;
    if (unit === 'count_per_1000') return `${fmtRate(v)} per 1,000 residents`;
    return String(v);
  }
  function fmtBound(unit, v) {
    if (unit === 'proportion') return `${(v * 100).toFixed(1)}%`;
    if (unit === 'count_per_1000') return fmtRate(v);
    return String(v);
  }
  const fmtRate = (v) => v.toFixed(v < 10 ? 2 : 1);
  function fmtInterval(unit, lo, hi) {
    const high = hi === -1 ? 'longer than observed' : fmtBound(unit, hi);
    return `${fmtBound(unit, lo)} to ${high}`;
  }

  function windowLabel(start, end) {
    const d = daysBetween(start, end) + 1;
    if (d >= 85 && d <= 95) return 'Last 90 days';
    if (d >= 360 && d <= 370) return 'Last 12 months';
    return `${fmtDate(start)} to ${fmtDate(end)}`;
  }

  // ---- data status and the five panels ----------------------------------------

  function renderStatus() {
    const m = state.manifest;
    const p = m.pipelines['311'];
    const box = $('#data-status');
    box.replaceChildren();
    if (!p) { box.append('No published data yet.'); return; }
    const age = daysBetween(p.data_current_through, todayChicago());
    state.fresh = age <= p.freshness_limit_days;
    const v = p.validation;
    box.append(
      el('strong', {}, '311 data current through ', fmtDate(p.data_current_through)), '. ',
      `Source validation ${v.status === 'pass' ? 'passed' : 'FAILED'} `,
      `(${v.summary.checks_passed} of ${v.summary.checks_run} checks) on ${fmtDate(v.run_date)}. `,
      `${v.record_counts.included_primary_in_city.toLocaleString()} requests inside city limits after removing duplicates.`,
    );
    if (!state.fresh) {
      box.append(el('div', { class: 'gate' },
        `This data is ${age} days old, past the ${p.freshness_limit_days}-day freshness limit, `,
        'so its numbers are hidden until the pipeline runs again.'));
    }
  }

  function panelState(key, p) {
    if (key === '311') {
      const any = Object.values(p.publish || {}).some((g) => g.publishable);
      return any ? ['live', 'Live'] : ['collecting', 'Computed, not yet published'];
    }
    if (p.status === 'collecting') return ['collecting', `Collecting since ${fmtDate(p.collecting_since)}`];
    if (p.status === 'blocked') return ['blocked', 'Blocked'];
    if (p.status === 'in_development') return ['in_development', 'In development'];
    return [p.status, p.status];
  }

  function renderPanels() {
    const grid = $('#panel-grid');
    grid.replaceChildren();
    for (const key of PANEL_ORDER) {
      const p = state.manifest.pipelines[key];
      if (!p) continue;
      const [cls, label] = panelState(key, p);
      const note = key === '311'
        ? 'Resolution times and re-reports for eight common request types, by ZIP, council district and address.'
        : p.note;
      grid.append(el('article', { class: 'card panel' },
        el('h3', {}, p.title),
        el('div', { class: `state state-${cls}` }, label),
        el('p', {}, note),
        key === '311' ? el('p', {}, el('a', { href: '#compare' }, 'Compare areas')) : null));
    }
  }

  // ---- metric tables -----------------------------------------------------------

  // rows: array of objects for one geography. Picks the row for this metric,
  // variant, request type and window.
  const pick = (rows, metric, variant, type, win) => (rows || []).find((r) =>
    r.metric === metric && r.variant === variant && r.subgroup === type &&
    r.window_start === win.start && r.window_end === win.end);

  function cellContent(spec, r, geo) {
    if (!r && geo && spec.geographies && !spec.geographies.includes(geo)) {
      return el('span', { class: 'muted' }, 'Not reported for this kind of area');
    }
    if (!r) return el('span', { class: 'muted' }, 'No requests in this window');
    if (r.suppressed && spec.min_population) {
      return el('span', { class: 'muted' },
        `Fewer than ${spec.min_population.toLocaleString()} residents inside the city, too few for a rate `,
        `(${r.n.toLocaleString()} request${r.n === 1 ? '' : 's'})`);
    }
    if (r.suppressed) {
      return el('span', { class: 'muted' },
        `Too few requests to report (n = ${r.n.toLocaleString()}; needs ${spec.min_n})`);
    }
    return el('div', {},
      el('div', {}, fmtValue(spec.unit, r.value)),
      el('div', { class: 'ci' }, `95% interval ${fmtInterval(spec.unit, r.ci_low, r.ci_high)}`),
      el('div', { class: 'ci' }, `n = ${r.n.toLocaleString()}`));
  }

  // A shared scale per table row so the interval bars can be compared by eye.
  function intervalBar(r, lo, hi, ref) {
    if (!r || r.suppressed) return null;
    const x = (v) => `${Math.max(0, Math.min(100, ((v - lo) / (hi - lo || 1)) * 100))}%`;
    const top = r.ci_high === -1 ? hi : r.ci_high;
    return el('div', { class: 'interval', 'aria-hidden': 'true' },
      el('div', { class: 'axis' }),
      el('div', { class: 'range', style: { left: x(r.ci_low), width: `calc(${x(top)} - ${x(r.ci_low)})` } }),
      ref != null ? el('div', { class: 'ref', style: { left: x(ref) }, title: 'Citywide' }) : null,
      el('div', { class: 'point', style: { left: x(r.value) } }));
  }

  function verdict(a, b) {
    if (!a || !b || a.suppressed || b.suppressed) return '';
    const aHi = a.ci_high === -1 ? Infinity : a.ci_high;
    const bHi = b.ci_high === -1 ? Infinity : b.ci_high;
    if (a.ci_low <= bHi && b.ci_low <= aHi) return 'Intervals overlap: not clearly different.';
    return 'Intervals do not overlap: the difference is larger than the uncertainty.';
  }

  function gateBox(g) {
    const n = g.missing.length;
    return el('details', { class: 'gate' },
      el('summary', {}, `Not yet published: ${n} of 6 publication conditions ${n === 1 ? 'is' : 'are'} unmet`,
        state.manifest.preview ? ' (numbers below are shown for review only)' : ''),
      el('ul', {}, g.missing.map((m) => el('li', {}, m))));
  }

  // columns: [{label, rows, geo}] where rows are objects for one geography
  // and geo is its geo_type. The verdict compares the first two columns.
  // Demand (requests per resident) is shown last, under its own heading, so
  // volume is never read as a measure of service quality.
  function renderMetricTable(columns, type, win) {
    const p = state.manifest.pipelines['311'];
    const wrap = el('div', {});
    if (!state.fresh) return wrap;
    const target = (p.targets || []).find((t) => t.request_type === type);
    const isDemand = (spec) => spec.unit === 'count_per_1000';
    const ordered = Object.entries(p.specs).sort(([, a], [, b]) => isDemand(a) - isDemand(b));
    let demandShown = false;
    for (const [id, spec] of ordered) {
      if (isDemand(spec) && !demandShown) {
        demandShown = true;
        wrap.append(el('h4', { class: 'subhead' }, 'Demand: how often residents report'),
          el('p', { class: 'fineprint' }, 'Requests per resident reflect awareness of 311 and willingness ',
            'to report as much as conditions. They say nothing about how well the city responds.'));
      }
      const gate = p.publish[id];
      const shown = !gate || gate.publishable || state.manifest.preview;
      const block = el('div', { class: 'metric' },
        el('div', {},
          el('span', { class: 'metric-title' }, spec.title),
          el('span', { class: 'metric-kind' },
            spec.promise_kind === 'official' ? 'measured against an official target' : 'compared with the citywide figure',
            ` · spec v${spec.version}${spec.status === 'frozen' ? '' : ` (${spec.status})`}`)));
      if (id === 'pct_within_target' && target) {
        block.append(el('div', { class: 'ci' }, 'City target: ',
          `${target.target_low_bd} to ${target.target_high_bd} business days (`,
          el('a', { href: target.target_source_url, rel: 'noopener' }, 'source'), ')'));
      }
      if (gate && !gate.publishable) block.append(gateBox(gate));
      if (!shown) { wrap.append(block); continue; }

      const prim = columns.map((c) => pick(c.rows, id, 'primary', type, win));
      if (prim.every((r) => !r)) {
        block.append(el('p', { class: 'muted' }, id === 'pct_within_target'
          ? 'Only reported for request types with an official city target.'
          : 'Not computed for this request type yet.'));
        wrap.append(block);
        continue;
      }
      block.append(valueTable(columns, prim, spec));
      const v = verdict(prim[0], prim[1]);
      if (v) block.append(el('p', { class: 'verdict' }, `${columns[0].label} vs ${columns[1].label}: ${v}`));

      const variants = [...new Set(columns.flatMap((c) => (c.rows || [])
        .filter((r) => r.metric === id && r.variant !== 'primary' && r.subgroup === type).map((r) => r.variant)))];
      if (variants.length) {
        block.append(el('details', {},
          el('summary', {}, 'Same metric under other thresholds'),
          variants.map((vn) => el('div', {},
            el('p', { class: 'ci' }, VARIANT_LABELS[vn] || vn),
            valueTable(columns, columns.map((c) => pick(c.rows, id, vn, type, win)), spec)))));
      }
      wrap.append(block);
    }
    return wrap;
  }

  function valueTable(columns, rows, spec) {
    const live = rows.filter((r) => r && !r.suppressed);
    const lo = Math.min(...live.map((r) => r.ci_low));
    const hi = Math.max(...live.map((r) => (r.ci_high === -1 ? r.value * 1.5 : r.ci_high)));
    const ref = live.length ? live[0].citywide_median : null;
    return el('div', { class: 'table-scroll' }, el('table', {},
      el('thead', {}, el('tr', {}, columns.map((c) => el('th', {}, c.label)))),
      el('tbody', {}, el('tr', {}, rows.map((r, i) => el('td', { class: 'num' },
        cellContent(spec, r, columns[i].geo), live.length ? intervalBar(r, lo, hi, ref) : null))))));
  }

  // ---- who lives here (ACS context, D20) ---------------------------------------------

  function fmtDemo(unit, v, moe) {
    if (v == null) return ['', ''];
    if (unit === 'proportion') return [`${(v * 100).toFixed(0)}%`, `± ${(moe * 100).toFixed(0)} pts`];
    if (unit === 'dollars') return [`$${Math.round(v).toLocaleString()}`, `± $${Math.round(moe).toLocaleString()}`];
    return [Math.round(v).toLocaleString(), `± ${Math.round(moe).toLocaleString()}`];
  }

  // areas: [{label, geo, id}]. Returns null when no area has demographics.
  function renderDemographics(areas) {
    const d = state.demo;
    if (!d) return null;
    const found = areas.map((a) => ((d.areas[a.geo] || {})[a.id]) || null);
    if (found.every((f) => !f)) return null;
    const partial = areas.map((a, i) => [a, found[i]])
      .filter(([, f]) => f && f.share_in_city != null && f.share_in_city < 0.98);
    return el('div', { class: 'demographics' },
      el('h3', {}, 'Who lives here'),
      el('p', { class: 'fineprint' }, 'Context for the comparison, not an explanation of it. ',
        'Differences in who lives in an area do not show that the city treats it differently.'),
      el('div', { class: 'table-scroll' }, el('table', {},
        el('thead', {}, el('tr', {}, el('th', {}, ''), areas.map((a) => el('th', {}, a.label)))),
        el('tbody', {}, d.measures.map((m, mi) => el('tr', {},
          el('th', { scope: 'row', title: m.note }, m.label),
          found.map((f) => {
            const cell = f && f.values[mi];
            if (!cell || cell[0] == null) return el('td', { class: 'muted' }, 'n/a');
            const [v, moe] = fmtDemo(m.unit, cell[0], cell[1]);
            return el('td', { class: 'num' }, v, ' ', el('span', { class: 'ci' }, moe),
              cell[2] === 'low' ? el('div', { class: 'ci' }, 'Low reliability') : null);
          })))))),
      partial.length ? el('p', { class: 'fineprint' }, partial.map(([a, f]) =>
        `${a.label}: ${Math.round(f.share_in_city * 100)}% of its residents live inside the city. `),
        'Figures cover only that part.') : null,
      el('p', { class: 'fineprint' },
        `American Community Survey ${d.acs_vintage} 5-year estimates, for the part of each area inside `,
        'the City of Memphis. Block-group estimates are split across areas using 2020 Census block ',
        'populations. ± is the 90% margin of error (the 311 figures above use 95% intervals). ',
        '"Low reliability" means the margin is large relative to the estimate.'));
  }

  // ---- area comparison -----------------------------------------------------------

  function areaOptions(select, selected) {
    const groups = [
      ['citywide', 'Citywide', () => 'City of Memphis'],
      ['reference_neighborhood', 'Reference neighborhoods', (id) => id],
      ['council_district', 'Council districts', (id) => `Council District ${id}`],
      ['super_district', 'Super districts', (id) => `Super District ${id}`],
      ['zcta', 'ZIP codes', (id) => `ZIP ${id}`],
    ];
    select.replaceChildren();
    for (const [g, label, name] of groups) {
      const ids = Object.keys(state.areas[g] || {}).sort((a, b) => a.localeCompare(b, 'en', { numeric: true }));
      if (!ids.length) continue;
      select.append(el('optgroup', { label }, ids.map((id) =>
        el('option', { value: `${g}|${id}`, selected: `${g}|${id}` === selected }, name(id)))));
    }
  }

  function areaName(value) {
    const opt = [...$('#area-a').options].find((o) => o.value === value);
    return opt ? opt.textContent : value;
  }
  const areaRows = (value) => {
    const [g, id] = value.split('|');
    return ((state.areas[g] || {})[id] || []).map(asRow);
  };
  const areaColumn = (value) => {
    const [geo, id] = value.split('|');
    return { label: areaName(value), rows: areaRows(value), geo, id };
  };

  function windowsFrom(rows) {
    const seen = new Map();
    for (const r of rows) seen.set(`${r.window_start}|${r.window_end}`, { start: r.window_start, end: r.window_end });
    // Longest window (earliest start) first.
    return [...seen.values()].sort((a, b) => daysBetween(b.start, a.start));
  }

  function fillSelect(select, items, keep) {
    select.replaceChildren(...items.map(([v, t]) => el('option', { value: v, selected: v === keep }, t)));
  }

  function setupCompare() {
    const p = state.manifest.pipelines['311'];
    const result = $('#compare-result');
    const cityRows = Object.values(state.areas.citywide || {})[0] || [];
    if (!cityRows.length) {
      $('#compare-form').hidden = true;
      result.replaceChildren(el('div', { class: 'card' },
        el('p', {}, 'No 311 metric has passed the publication gate yet, so there is nothing to compare. ',
          'Each metric and what it still needs:'),
        renderMetricTable([{ label: '', rows: [] }, { label: '', rows: [] }], p.headline_types[0], {})));
      return;
    }
    areaOptions($('#area-a'), 'reference_neighborhood|Frayser');
    areaOptions($('#area-b'), 'citywide|' + Object.keys(state.areas.citywide)[0]);
    fillSelect($('#req-type'), p.headline_types.map((t) => [t, typeLabel(t)]), 'PW (SM)-Potholes');
    const wins = windowsFrom(cityRows.map(asRow));
    fillSelect($('#window'), wins.map((w) => [`${w.start}|${w.end}`, windowLabel(w.start, w.end)]));
    const draw = () => {
      const [start, end] = $('#window').value.split('|');
      const a = $('#area-a').value, b = $('#area-b').value;
      const cols = [areaColumn(a), areaColumn(b)];
      result.replaceChildren(el('div', { class: 'card' },
        renderMetricTable(cols, $('#req-type').value, { start, end }),
        renderDemographics(cols)));
    };
    $('#compare-form').addEventListener('change', draw);
    draw();
  }

  // ---- address lookup ---------------------------------------------------------------

  // The Census geocoder sends no CORS headers, so it is called with JSONP (H6).
  function censusGeocode(address) {
    return new Promise((resolve, reject) => {
      const cb = `mseGeo${Date.now()}`;
      const s = document.createElement('script');
      const done = () => { delete window[cb]; s.remove(); clearTimeout(timer); };
      const timer = setTimeout(() => { done(); reject(new Error('Census geocoder timed out')); }, 12000);
      window[cb] = (data) => {
        done();
        const m = data && data.result && data.result.addressMatches && data.result.addressMatches[0];
        resolve(m ? { lat: m.coordinates.y, lon: m.coordinates.x, label: m.matchedAddress, source: 'U.S. Census Bureau geocoder' } : null);
      };
      s.onerror = () => { done(); reject(new Error('Census geocoder unavailable')); };
      s.src = 'https://geocoding.geo.census.gov/geocoder/locations/onelineaddress?' + new URLSearchParams({
        address, benchmark: 'Public_AR_Current', format: 'jsonp', callback: cb });
      document.head.append(s);
    });
  }

  async function nominatimGeocode(address) {
    const res = await fetch('https://nominatim.openstreetmap.org/search?' + new URLSearchParams({
      q: address, format: 'jsonv2', limit: '1', countrycodes: 'us',
      viewbox: '-90.31,35.27,-89.63,34.99', bounded: '1' }));
    if (!res.ok) return null;
    const [m] = await res.json();
    return m ? { lat: +m.lat, lon: +m.lon, label: m.display_name, source: 'OpenStreetMap Nominatim' } : null;
  }

  async function geocode(address) {
    try {
      const hit = await censusGeocode(address);
      if (hit) return hit;
    } catch (e) { /* fall through to Nominatim */ }
    return nominatimGeocode(address);
  }

  async function hexShard(parent) {
    if (!state.hex.has(parent)) state.hex.set(parent, getJSON(`311/hex/${parent}.json`));
    return state.hex.get(parent);
  }
  async function pointShard(parent) {
    if (!state.points.has(parent)) state.points.set(parent, getJSON(`311/points/${parent}.json`));
    return state.points.get(parent);
  }

  // Individual requests whose location falls in the address's seven cells.
  async function nearbyRequests(disk) {
    const inDisk = new Set(disk);
    const parents = [...new Set(disk.map((c) => h3.cellToParent(c, 6)))];
    const out = [];
    for (const shard of await Promise.all(parents.map(pointShard))) {
      if (!shard) continue;
      const col = Object.fromEntries(shard.columns.map((c, i) => [c, shard.by_column[i]]));
      for (let i = 0; i < col.id.length; i++) {
        if (!inDisk.has(h3.latLngToCell(col.lat[i], col.lon[i], 9))) continue;
        out.push({ id: col.id[i], type: shard.types[col.type[i]], opened: col.opened[i],
          closed: col.closed[i], bd: col.bd[i], dup: col.dup[i] === 1 });
      }
    }
    return out.sort((a, b) => (a.opened < b.opened ? 1 : -1));
  }

  function requestsTable(reqs) {
    const primary = reqs.filter((r) => !r.dup);
    const counts = new Map();
    for (const r of primary) counts.set(r.type, (counts.get(r.type) || 0) + 1);
    const recent = reqs.slice(0, 15);
    return el('div', { class: 'requests' },
      el('h3', {}, 'Requests near this address in the last 12 months'),
      reqs.length ? null : el('p', { class: 'muted' }, 'None of the eight tracked request types.'),
      counts.size ? el('div', { class: 'tags' }, [...counts].sort((a, b) => b[1] - a[1])
        .map(([t, n]) => el('span', { class: 'tag' }, `${typeLabel(t)}: ${n}`))) : null,
      counts.size ? el('p', { class: 'fineprint' },
        'Counts exclude near-duplicates (the same type within 50 m and 7 days of an earlier request). ',
        'Volume reflects how often residents report, not how well the city performs.') : null,
      recent.length ? el('div', { class: 'table-scroll' }, el('table', {},
        el('thead', {}, el('tr', {}, ['Opened', 'Type', 'Closed', 'Business days', 'Request'].map((h) => el('th', {}, h)))),
        el('tbody', {}, recent.map((r) => el('tr', {},
          el('td', {}, fmtDate(r.opened)),
          el('td', {}, typeLabel(r.type), r.dup ? el('span', { class: 'ci' }, ' (duplicate)') : null),
          el('td', {}, r.closed ? fmtDate(r.closed) : 'Still open'),
          el('td', { class: 'num' }, r.bd == null ? '' : r.bd),
          el('td', { class: 'num' }, r.id)))))) : null);
  }

  async function lookup(ev) {
    ev.preventDefault();
    const out = $('#lookup-result');
    const btn = ev.target.querySelector('button');
    const address = $('#address').value.trim();
    if (!address) return;
    btn.disabled = true;
    out.replaceChildren(el('p', { class: 'muted' }, 'Finding that address…'));
    try {
      const hit = await geocode(/memphis/i.test(address) ? address : `${address}, Memphis, TN`);
      if (!hit) {
        out.replaceChildren(el('p', {}, 'No match for that address. Try including the street number, street name and ZIP code.'));
        return;
      }
      const cell = h3.latLngToCell(hit.lat, hit.lon, 9);
      const disk = h3.gridDisk(cell, 1);
      const shard = await hexShard(h3.cellToParent(cell, 6));
      const geo = shard && (shard.geo[cell] || disk.map((c) => shard.geo[c]).find(Boolean));
      const head = el('div', { class: 'result-head' },
        el('div', { class: 'addr' }, hit.label),
        el('div', { class: 'fineprint' }, `Located by the ${hit.source}.`));
      if (!geo) {
        out.replaceChildren(head, el('p', {}, 'This address is outside the area this site covers (the City of Memphis), ',
          'or no tracked 311 requests have been filed near it.'));
        return;
      }
      const [zip, district] = geo;
      head.append(el('div', { class: 'tags' },
        zip ? el('span', { class: 'tag' }, `ZIP ${zip}`) : null,
        district ? el('span', { class: 'tag' }, `Council District ${district}`) : null));

      const p = state.manifest.pipelines['311'];
      const near = ((shard.metrics && shard.metrics[cell]) || []).map(asRow);
      const city = Object.values(state.areas.citywide || {})[0] || [];
      const cityId = Object.keys(state.areas.citywide || {})[0];
      const columns = [
        { label: 'Near this address', rows: near, geo: 'h3_9' },
        { label: 'Citywide', rows: city.map(asRow), geo: 'citywide', id: cityId },
        zip ? { label: `ZIP ${zip}`, rows: ((state.areas.zcta || {})[zip] || []).map(asRow), geo: 'zcta', id: zip } : null,
        district ? { label: `District ${district}`, rows: ((state.areas.council_district || {})[district] || []).map(asRow),
          geo: 'council_district', id: district } : null,
      ].filter(Boolean);

      const typeSel = el('select', { 'aria-label': 'Request type' });
      fillSelect(typeSel, p.headline_types.map((t) => [t, typeLabel(t)]), 'PW (SM)-Potholes');
      const wins = windowsFrom(columns[1].rows);
      const winSel = el('select', { 'aria-label': 'Window' });
      // Longest window first: it matches the 12-month request list below and
      // gives small areas the best chance of clearing the minimum n.
      fillSelect(winSel, wins.map((w) => [`${w.start}|${w.end}`, windowLabel(w.start, w.end)]));
      const tableBox = el('div', {});
      const draw = () => {
        const [start, end] = (winSel.value || '|').split('|');
        tableBox.replaceChildren(renderMetricTable(columns, typeSel.value, { start, end }));
      };
      typeSel.addEventListener('change', draw);
      winSel.addEventListener('change', draw);
      draw();

      const reqs = await nearbyRequests(disk);
      const anyShown = state.manifest.preview || Object.values(p.publish).some((g) => g.publishable);
      out.replaceChildren(head, el('div', { class: 'card' },
        el('h3', {}, 'City services (311)'),
        anyShown ? el('div', { class: 'compare-form' },
          el('label', {}, 'Request type', typeSel),
          wins.length ? el('label', {}, 'Window', winSel) : null) : null,
        tableBox,
        requestsTable(reqs),
        renderDemographics(columns.filter((c) => c.id))),
        el('p', { class: 'fineprint' }, 'Transit, power, food safety and investment are not live yet; see the five systems below.'));
    } catch (e) {
      out.replaceChildren(el('p', {}, `Something went wrong: ${e.message}`));
    } finally {
      btn.disabled = false;
    }
  }

  // ---- start ---------------------------------------------------------------------------

  async function init() {
    try {
      state.manifest = await getJSON('manifest.json');
      if (!state.manifest) throw new Error('manifest.json not found; run site/build_site_data.R');
    } catch (e) {
      $('#data-status').textContent = `Could not load the site data (${e.message}).`;
      return;
    }
    state.manifest.columns.forEach((c, i) => { state.cols[c] = i; });
    $('#preview-banner').hidden = !state.manifest.preview;
    renderStatus();
    renderPanels();
    if (state.manifest.pipelines['311']) {
      state.areas = (await getJSON('311/areas.json')) || {};
      if (state.manifest.demographics) state.demo = await getJSON(state.manifest.demographics.file);
      // Gated builds can write empty geographies as [] rather than {}.
      for (const g of Object.keys(state.areas)) if (Array.isArray(state.areas[g])) state.areas[g] = {};
      setupCompare();
    }
    $('#lookup-form').addEventListener('submit', lookup);
  }

  init();
})();
