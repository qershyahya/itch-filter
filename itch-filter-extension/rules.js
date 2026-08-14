var CF = (() => {
  var __defProp = Object.defineProperty;
  var __getOwnPropDesc = Object.getOwnPropertyDescriptor;
  var __getOwnPropNames = Object.getOwnPropertyNames;
  var __hasOwnProp = Object.prototype.hasOwnProperty;
  var __export = (target, all) => {
    for (var name in all)
      __defProp(target, name, { get: all[name], enumerable: true });
  };
  var __copyProps = (to, from, except, desc) => {
    if (from && typeof from === "object" || typeof from === "function") {
      for (let key of __getOwnPropNames(from))
        if (!__hasOwnProp.call(to, key) && key !== except)
          __defProp(to, key, { get: () => from[key], enumerable: !(desc = __getOwnPropDesc(from, key)) || desc.enumerable });
    }
    return to;
  };
  var __toCommonJS = (mod) => __copyProps(__defProp({}, "__esModule", { value: true }), mod);

  // ../itch-content-filter/overlay/src/common/contentFilter/rules.ts
  var rules_exports = {};
  __export(rules_exports, {
    classify: () => classify,
    parseList: () => parseList
  });
  var norm = (s) => (s ?? "").toLowerCase();
  var slug = (s) => norm(s).replace(/[\s_]+/g, "-");
  function hasBannedKeyword(text, banned) {
    const hay = norm(text);
    for (const raw of banned) {
      const kw = norm(raw);
      if (!kw) continue;
      const re = /^[a-z0-9]+$/.test(kw) ? new RegExp(`\\b${kw.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")}\\b`, "i") : null;
      if (re ? re.test(hay) : hay.includes(kw)) return raw;
    }
    return null;
  }
  function classify(c, cfg) {
    if (!cfg.enabled) return { blocked: false, reason: "disabled" };
    if (c.id && cfg.allowedIds.includes(c.id)) {
      return { blocked: false, reason: "allow-override" };
    }
    if (c.id && cfg.blockedIds.includes(c.id)) return { blocked: true, reason: "id" };
    if (c.author && cfg.blockedCreators.map(norm).includes(norm(c.author))) {
      return { blocked: true, reason: `creator:${c.author}` };
    }
    if (c.adultWarning) return { blocked: true, reason: "adult-flag" };
    if (c.tags && c.tags.length) {
      const tagSet = new Set(c.tags.map(slug));
      for (const bt of cfg.bannedTags) {
        if (tagSet.has(slug(bt))) return { blocked: true, reason: `tag:${bt}` };
      }
    }
    const blob = [c.title, c.text, c.author].filter(Boolean).join("  ");
    const hit = hasBannedKeyword(blob, cfg.bannedKeywords);
    if (hit) return { blocked: true, reason: `keyword:${hit}` };
    return { blocked: false, reason: "ok" };
  }
  function parseList(text) {
    return text.split(/\r?\n/).map((l) => l.replace(/#.*$/, "").trim().toLowerCase()).filter(Boolean);
  }
  return __toCommonJS(rules_exports);
})();
