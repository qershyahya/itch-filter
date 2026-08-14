/* Background service worker: owns config, verifies game/jam pages (cross-site
   fetch is allowed here via host_permissions — no CORS problem). */
importScripts("rules.js", "defaultConfig.js");

/* ---- GitHub is the single source of truth for the lists ----
   On startup, on every itch.io page load (throttled), and hourly, the worker
   fetches filter-config.json, checksums it, and pulls when it differs. It also
   re-asserts GitHub's lists over any local edit, so the only way to change what
   is blocked is to edit the file in the GitHub account — a student cannot loosen
   it on the machine. pinHash/pinSalt stay local. Fails open (keeps last lists)
   if GitHub is unreachable, so blocking never silently turns off. */
const SYNC_URL = "https://raw.githubusercontent.com/qershyahya/itch-filter/main/filter-config.json";
const SYNC_FIELDS = ["enabled", "bannedTags", "bannedKeywords", "blockedSlugs", "blockedCreators", "allowedIds", "blockedIds"];
const SYNC_THROTTLE_MS = 120000; // network floor: at most one pull per 2 min from page-load pings
let lastSyncAt = 0, syncing = null;

async function sha256(str) {
  const buf = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(str));
  return [...new Uint8Array(buf)].map((b) => b.toString(16).padStart(2, "0")).join("");
}
const pick = (o, keys) => JSON.stringify(keys.map((k) => o?.[k]));

async function syncRemote(force = false) {
  if (!SYNC_URL) return;
  if (!force && Date.now() - lastSyncAt < SYNC_THROTTLE_MS) return; // page-load throttle
  if (syncing) return syncing;                                     // coalesce concurrent pulls
  syncing = (async () => {
    try {
      const text = await fetch(SYNC_URL, { cache: "no-store" }).then((r) => (r.ok ? r.text() : Promise.reject(r.status)));
      lastSyncAt = Date.now();
      const hash = await sha256(text);
      const remote = JSON.parse(text);
      const { config, cfgHash } = await chrome.storage.local.get(["config", "cfgHash"]);
      const cur = config || self.DEFAULT_CONFIG;
      const next = { ...cur }; // keeps pinHash/pinSalt
      for (const k of SYNC_FIELDS) if (Array.isArray(remote[k]) || typeof remote[k] === "boolean") next[k] = remote[k];
      // write when the remote changed OR local lists drifted from remote (tamper revert)
      if (hash !== cfgHash || pick(next, SYNC_FIELDS) !== pick(cur, SYNC_FIELDS)) {
        await chrome.storage.local.set({ config: next, cfgHash: hash, lastSync: Date.now() });
      }
    } catch { /* fail-open: keep whatever lists we already have */ }
    finally { syncing = null; }
  })();
  return syncing;
}

// seed default config on install, then sync + schedule hourly pulls
chrome.runtime.onInstalled.addListener(async () => {
  const { config } = await chrome.storage.local.get("config");
  if (!config) await chrome.storage.local.set({ config: self.DEFAULT_CONFIG });
  chrome.alarms.create("cf-sync", { periodInMinutes: 60 });
  syncRemote(true);
});
chrome.runtime.onStartup.addListener(() => syncRemote(true));   // every Chrome reload
chrome.alarms.onAlarm.addListener((a) => { if (a.name === "cf-sync") syncRemote(true); });

let cfgCache = null;
async function getConfig() {
  if (cfgCache) return cfgCache;
  const { config } = await chrome.storage.local.get("config");
  cfgCache = config || self.DEFAULT_CONFIG;
  return cfgCache;
}
chrome.storage.onChanged.addListener((changes) => {
  if (changes.config) cfgCache = changes.config.newValue;
});

// per-URL verdict cache + concurrency cap
const pageCache = new Map();
const MAX = 24;
let active = 0;
const q = [];
const acquire = () =>
  new Promise((res) => (active < MAX ? (active++, res()) : q.push(() => (active++, res()))));
const release = () => { active--; q.shift()?.(); };

async function fetchHtml(url) {
  let err;
  for (let i = 0; i < 3; i++) {
    const ctrl = new AbortController();
    const t = setTimeout(() => ctrl.abort(), 6000);
    try {
      const r = await fetch(url, { signal: ctrl.signal, credentials: "omit" });
      if (!r.ok) throw new Error("http " + r.status);
      return await r.text();
    } catch (e) { err = e; if (i < 2) await new Promise((s) => setTimeout(s, 400 * (i + 1))); }
    finally { clearTimeout(t); }
  }
  throw err;
}

// Jam entry "rate" pages (/jam/<slug>/rate/<id>) carry no game_info_panel_widget,
// so tags can't be read from them. Follow to the real game page and verify that.
async function resolveGameUrl(url) {
  if (!/\/jam\/[^/]+\/rate\/\d+/.test(url)) return url;
  const html = await fetchHtml(url);
  const m = html.match(/href="(https?:\/\/[a-z0-9-]+\.itch\.io\/[a-z0-9-]+)"/i); // first real game-page link
  if (!m) throw new Error("unresolved rate url"); // fail-closed: no game page → stay hidden
  return m[1];
}

async function checkGame(url) {
  const cfg = await getConfig();
  if (!cfg.enabled) return { blocked: false, reason: "disabled" };
  const cached = pageCache.get(url);
  if (cached) return cached;
  await acquire();
  try {
    const realUrl = await resolveGameUrl(url);
    const html = await fetchHtml(realUrl);
    // tags/genre from the game's "More information" panel(s), any section prefix
    const panels = [...html.matchAll(/game_info_panel_widget/g)]
      .map((m) => html.slice(m.index, m.index + 2500)).join("\n");
    const tags = [...new Set([
      ...[...panels.matchAll(/\/tag-([a-z0-9-]+)/g)].map((m) => m[1]),
      ...[...panels.matchAll(/\/genre-([a-z0-9-]+)/g)].map((m) => m[1]),
    ])];
    const adultWarning = /content_warning_outer|This game contains adult content/i.test(html);
    const title =
      (html.match(/<meta property="og:title" content="([^"]*)"/) || [])[1] ||
      (html.match(/<h1[^>]*class="[^"]*game_title[^"]*"[^>]*>([^<]+)</) || [])[1] || "";
    const ogDesc = (html.match(/<meta property="og:description" content="([^"]*)"/) || [])[1] || "";
    const fd = (html.match(/class="formatted_description[^"]*"[^>]*>([\s\S]{0,6000})/) || [])[1] || "";
    const text = ogDesc + " " + fd.replace(/<[^>]+>/g, " ");
    const v = CF.classify({ kind: "game", tags, adultWarning, title, text }, cfg);
    pageCache.set(url, v);            // cache only real, page-backed verdicts
    return v;
  } catch {
    return { blocked: true, reason: "unverified" }; // fail-closed, not cached → retried
  } finally { release(); }
}

chrome.runtime.onMessage.addListener((msg, _sender, sendResponse) => {
  if (msg?.type === "check-game") { checkGame(msg.url).then(sendResponse); return true; }
  if (msg?.type === "sync-now") { syncRemote(false).then(() => sendResponse(true)); return true; } // page-load freshness check
});
