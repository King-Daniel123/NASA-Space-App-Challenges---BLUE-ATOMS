// Atomic Space - NASA data snapshot builder (build tool, not game code).
//
// The game itself is written in Object Pascal. This small Node script only
// downloads open NASA data so the game ships with a real, offline-safe
// snapshot. The game refreshes the same feeds live in the browser when it can.
//
// Run:  node scripts/fetch-nasa-data.mjs
// Out:  public/data/nasa-snapshot.json
//
// Sources (all open NASA data):
//   EONET v3  - Earth Observatory Natural Event Tracker (natural events)
//   DONKI     - Space Weather Database Of Notifications, Knowledge, Information
//   NeoWs     - Near Earth Object Web Service (asteroid 99942 Apophis)
//
// AI-assistance note: this script was written with the help of Claude (Anthropic).

import { writeFile, readFile, mkdir } from 'node:fs/promises';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const outFile = resolve(here, '..', 'public', 'data', 'nasa-snapshot.json');
const API_KEY = process.env.NASA_API_KEY || 'DEMO_KEY';

const today = new Date();
const iso = (d) => d.toISOString().slice(0, 10);
const daysAgo = (n) => { const d = new Date(today); d.setUTCDate(d.getUTCDate() - n); return d; };

async function getJson(url) {
  const r = await fetch(url);
  if (!r.ok) throw new Error(`HTTP ${r.status} for ${url.replace(API_KEY, 'KEY')}`);
  return r.json();
}

const round = (x, n = 2) => Math.round(x * 10 ** n) / 10 ** n;

// ---- EONET: natural events from the last 45 days -------------------------
async function eonet() {
  const data = await getJson('https://eonet.gsfc.nasa.gov/api/v3/events?days=45&status=all');
  const out = [];
  for (const e of data.events) {
    const g = e.geometry && e.geometry[e.geometry.length - 1];
    if (!g) continue;
    let lon; let lat;
    if (g.type === 'Point') {
      [lon, lat] = g.coordinates;
    } else if (g.type === 'Polygon' && g.coordinates[0] && g.coordinates[0].length) {
      // Use the centre of the polygon's outer ring.
      const ring = g.coordinates[0];
      lon = ring.reduce((s, p) => s + p[0], 0) / ring.length;
      lat = ring.reduce((s, p) => s + p[1], 0) / ring.length;
    } else continue;
    out.push({
      id: e.id,
      t: e.title,
      c: e.categories[0].id,
      d: (g.date || '').slice(0, 10),
      lon: round(lon),
      lat: round(lat),
    });
  }
  // Keep the snapshot small but representative: every non-wildfire event,
  // plus an even sample of wildfires (there are thousands).
  const fires = out.filter((e) => e.c === 'wildfires');
  const other = out.filter((e) => e.c !== 'wildfires');
  const step = Math.max(1, Math.floor(fires.length / 260));
  const sampled = fires.filter((_, i) => i % step === 0);
  return { total: out.length, events: other.concat(sampled) };
}

// ---- DONKI: one year of notable space weather ----------------------------
async function donki() {
  const s = iso(daysAgo(360));
  const e = iso(today);
  const base = 'https://ccmc.gsfc.nasa.gov/DONKI/WS/get';
  const out = [];
  const seen = new Set();
  const add = (rec) => { const key = `${rec.k}|${rec.d}|${rec.cls}`; if (!seen.has(key)) { seen.add(key); out.push(rec); } };
  // The service rejects long date ranges, so ask for 30 days at a time.
  for (let back = 360; back > 0; back -= 30) {
    const ws = iso(daysAgo(back));
    const we = iso(daysAgo(Math.max(0, back - 30)));
    for (const kind of ['FLR', 'GST', 'SEP']) {
      try {
        const rows = await getJson(`${base}/${kind}?startDate=${ws}&endDate=${we}`);
        for (const r of rows) {
          if (kind === 'FLR') {
            const cls = r.classType || '';
            if (!/^(X|M[5-9])/.test(cls)) continue; // strong flares only
            add({ k: 'FLR', d: (r.peakTime || r.beginTime || '').slice(0, 10), cls, src: r.sourceLocation || '', link: r.link || '' });
          } else if (kind === 'GST') {
            const kp = Math.max(0, ...(r.allKpIndex || []).map((k) => k.kpIndex || 0));
            add({ k: 'GST', d: (r.startTime || '').slice(0, 10), cls: `Kp ${kp}`, kp, link: r.link || '' });
          } else {
            add({ k: 'SEP', d: (r.eventTime || '').slice(0, 10), cls: 'SEP', link: r.link || '' });
          }
        }
      } catch (err) { console.warn(`DONKI ${kind} ${ws}..${we} skipped: ${err.message}`); }
    }
  }
  out.sort((a, b) => (a.d < b.d ? -1 : a.d > b.d ? 1 : 0));
  return { from: s, to: e, events: out };
}

// ---- NeoWs: asteroid 99942 Apophis ---------------------------------------
async function apophis() {
  const a = await getJson(`https://api.nasa.gov/neo/rest/v1/neo/2099942?api_key=${API_KEY}`);
  const ca = (a.close_approach_data || []).find((c) => c.close_approach_date === '2029-04-13');
  return {
    name: a.name,
    diameterMinM: round(a.estimated_diameter.meters.estimated_diameter_min, 0),
    diameterMaxM: round(a.estimated_diameter.meters.estimated_diameter_max, 0),
    hazardous: !!a.is_potentially_hazardous_asteroid,
    approachDate: ca ? ca.close_approach_date : '2029-04-13',
    approachFull: ca ? ca.close_approach_date_full : '',
    missKm: ca ? round(Number(ca.miss_distance.kilometers), 0) : 0,
    missLunar: ca ? round(Number(ca.miss_distance.lunar), 3) : 0,
    relVelKmS: ca ? round(Number(ca.relative_velocity.kilometers_per_second), 2) : 0,
    periodDays: round(Number(a.orbital_data.orbital_period), 1),
    inclinationDeg: round(Number(a.orbital_data.inclination), 2),
    url: a.nasa_jpl_url,
  };
}

// Start from the previous snapshot, so a feed that is down or rate-limited
// today keeps its last good data instead of being wiped.
let previous = {};
try { previous = JSON.parse(await readFile(outFile, 'utf8')); } catch (err) { /* first run */ }

const snapshot = { generated: today.toISOString(), note: 'Open NASA data snapshot for the Atomic Space game. Refreshed live in the browser when possible.' };
for (const [name, fn] of [['eonet', eonet], ['donki', donki], ['apophis', apophis]]) {
  try {
    snapshot[name] = await fn();
    const n = snapshot[name].events ? snapshot[name].events.length : 1;
    console.log(`${name}: ok (${n} records)`);
  } catch (err) {
    snapshot[name] = previous[name] || null;
    console.error(`${name}: FAILED - ${err.message}` + (snapshot[name] ? ' (kept the previous data)' : ''));
  }
}
await mkdir(dirname(outFile), { recursive: true });
await writeFile(outFile, JSON.stringify(snapshot));
console.log('wrote', outFile);

// ---- GIBS: Blue Marble world map for the Earth scenario ------------------
// NASA Global Imagery Browse Services, layer BlueMarble_NextGeneration.
try {
  const mapUrl = 'https://gibs.earthdata.nasa.gov/wms/epsg4326/best/wms.cgi?SERVICE=WMS&REQUEST=GetMap&VERSION=1.3.0'
    + '&LAYERS=BlueMarble_NextGeneration&STYLES=&FORMAT=image/jpeg&CRS=EPSG:4326&BBOX=-90,-180,90,180&WIDTH=1024&HEIGHT=512';
  const r = await fetch(mapUrl);
  if (!r.ok) throw new Error(`HTTP ${r.status}`);
  const mapFile = resolve(here, '..', 'public', 'assets', 'earth_map.jpg');
  await writeFile(mapFile, Buffer.from(await r.arrayBuffer()));
  console.log('wrote', mapFile);
} catch (err) {
  console.error('earth map: FAILED -', err.message);
}
