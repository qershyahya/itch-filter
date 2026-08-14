const $ = (id) => document.getElementById(id);
const show = (id, on) => $(id).classList.toggle("hidden", !on);
const msg = (t) => ($("msg").textContent = t);
const lines = (a) => (a || []).join("\n");
const toArr = (s) => s.split(/\r?\n/).map((x) => x.trim()).filter(Boolean);

async function sha(pin, salt) {
  const buf = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(salt + ":" + pin));
  return [...new Uint8Array(buf)].map((b) => b.toString(16).padStart(2, "0")).join("");
}

async function getCfg() {
  const { config } = await chrome.storage.local.get("config");
  return config || {};
}

async function init() {
  const cfg = await getCfg();
  if (!cfg.pinHash) show("setpin", true);
  else show("lock", true);
}

$("createpin").onclick = async () => {
  const pin = $("newpin").value;
  if (pin.length < 4) return msg("PIN must be at least 4 characters.");
  const salt = crypto.randomUUID();
  const cfg = await getCfg();
  cfg.pinHash = await sha(pin, salt);
  cfg.pinSalt = salt;
  await chrome.storage.local.set({ config: cfg });
  show("setpin", false); openEditor(cfg); msg("PIN set.");
};

$("unlock").onclick = async () => {
  const cfg = await getCfg();
  const ok = cfg.pinHash === (await sha($("pin").value, cfg.pinSalt));
  if (!ok) return msg("Wrong PIN.");
  show("lock", false); openEditor(cfg); msg("");
};

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
    reviewReasonEntry: cfg.reviewReasonEntry || "",
  });
  await chrome.storage.local.set({ config: cfg });
  msg("Saved. Reload itch.io tabs to apply.");
};

init();
