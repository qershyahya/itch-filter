/* Background service worker: owns config, verifies game/jam pages (cross-site
   fetch is allowed here via host_permissions — no CORS problem). */
importScripts("rules.js", "defaultConfig.js");

/* ---- central list-sync from a GitHub raw JSON (edit the file → all machines
   follow within the hour; no reinstall). Leave SYNC_URL "" to disable.
   The JSON is the same shape as defaultConfig; only the list fields below are
   pulled. pinHash/pinSalt stay local. Fails open (keeps current config). ---- */
const SYNC_URL = ""; // e.g. "https://raw.githubusercontent.com/USER/REPO/main/filter-config.json"
const SYNC_FIELDS = ["enabled", "bannedTags", "bannedKeywords", "blockedSlugs", "blockedCreators", "allowedIds", "blockedIds"];

async function syncRemote() {
  if (!SYNC_URL) return;
  try {
    const remote = await fetch(SYNC_URL, { cache: "no-store" }).then((r) => (r.ok ? r.json() : Promise.reject(r.status)));
    const { config } = await chrome.storage.local.get("config");
    const next = { ...(config || self.DEFAULT_CONFIG) }; // keeps pinHash/pinSalt
    for (const k of SYNC_FIELDS) {
      if (Array.isArray(remote[k]) || typeof remote[k] === "boolean") next[k] = remote[k];
    }
    await chrome.storage.local.set({ config: next, lastSync: Date.now() });
  } catch { /* fail-open: keep whatever config we already have */ }
}

// seed default config on install, then sync + schedule hourly pulls
chrome.runtime.onInstalled.addListener(async () => {
  const { config } = await chrome.storage.local.get("config");
  if (!config) await chrome.storage.local.set({ config: self.DEFAULT_CONFIG });
  chrome.alarms.create("cf-sync", { periodInMinutes: 60 });
  syncRemote();
});
chrome.runtime.onStartup.addListener(syncRemote);
chrome.alarms.onAlarm.addListener((a) => { if (a.name === "cf-sync") syncRemote(); });

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

async function checkGame(url) {
  const cfg = await getConfig();
  if (!cfg.enabled) return { blocked: false, reason: "disabled" };
  const cached = pageCache.get(url);
  if (cached) return cached;
  await acquire();
  try {
    const html = await fetchHtml(url);
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
});
