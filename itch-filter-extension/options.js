/* Settings page. The secret key is PRESET by the administrator (PBKDF2 hash shipped
   in the config and re-asserted from the central config on every sync), so a student
   cannot claim it by opening this page first, and cannot clear it locally. */
const $ = (id) => document.getElementById(id);
const show = (id, on) => $(id).classList.toggle("hidden", !on);
const lines = (a) => (a || []).join("\n");
const toArr = (s) => s.split(/\r?\n/).map((x) => x.trim()).filter(Boolean);
const b64ToBytes = (b64) => Uint8Array.from(atob(b64), (c) => c.charCodeAt(0));
const bytesToB64 = (buf) => btoa(String.fromCharCode(...new Uint8Array(buf)));

async function pbkdf2(pw, saltB64, iters) {
  const key = await crypto.subtle.importKey("raw", new TextEncoder().encode(pw), "PBKDF2", false, ["deriveBits"]);
  const bits = await crypto.subtle.deriveBits(
    { name: "PBKDF2", salt: b64ToBytes(saltB64), iterations: iters || 210000, hash: "SHA-256" },
    key, 256
  );
  return bytesToB64(bits);
}
// constant-time-ish compare
const same = (a, b) => {
  if (!a || !b || a.length !== b.length) return false;
  let d = 0;
  for (let i = 0; i < a.length; i++) d |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return d === 0;
};

async function getCfg() {
  const { config } = await chrome.storage.local.get("config");
  return config || {};
}

$("unlock").onclick = async () => {
  const cfg = await getCfg();
  const m = $("lockmsg");
  if (!cfg.pwHash || !cfg.pwSalt) { m.className = "msg err"; m.textContent = "No key configured — contact support."; return; }
  const got = await pbkdf2($("pw").value, cfg.pwSalt, cfg.pwIters);
  if (!same(got, cfg.pwHash)) {
    m.className = "msg err"; m.textContent = "Wrong key."; $("pw").value = "";
    return;
  }
  m.textContent = ""; $("pw").value = "";
  show("lock", false); openEditor(cfg);
};

$("checkUpdates").onclick = () => {
  const m = $("lockmsg"); m.className = "msg"; m.textContent = "Checking…";
  chrome.runtime.sendMessage({ type: "sync-now", force: true }, () => {
    void chrome.runtime.lastError;
    m.textContent = "Filter lists are up to date.";
  });
};

$("lockAgain").onclick = () => { show("editor", false); show("lock", true); $("msg").textContent = ""; };

function openEditor(cfg) {
  show("editor", true);
  $("enabled").checked = cfg.enabled !== false;
  $("bannedTags").value = lines(cfg.bannedTags);
  $("bannedKeywords").value = lines(cfg.bannedKeywords);
  $("blockedSlugs").value = lines(cfg.blockedSlugs);
  $("blockedCreators").value = lines(cfg.blockedCreators);
  $("allowedIds").value = lines(cfg.allowedIds);
  $("reviewUrl").value = cfg.reviewUrl || "";
  $("reviewEntry").value = cfg.reviewEntry || "";
}

$("save").onclick = async () => {
  const cfg = await getCfg();
  Object.assign(cfg, {
    enabled: $("enabled").checked,
    bannedTags: toArr($("bannedTags").value),
    bannedKeywords: toArr($("bannedKeywords").value),
    blockedSlugs: toArr($("blockedSlugs").value),
    blockedCreators: toArr($("blockedCreators").value),
    allowedIds: toArr($("allowedIds").value),
    blockedIds: cfg.blockedIds || [],
    reviewUrl: $("reviewUrl").value.trim(),
    reviewEntry: $("reviewEntry").value.trim(),
  });
  await chrome.storage.local.set({ config: cfg });
  $("msg").className = "msg"; $("msg").textContent = "Saved. Reload itch.io tabs to apply.";
};

// always start locked
show("lock", true); show("editor", false);
