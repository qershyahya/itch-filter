/* Content script: runs on every itch.io page. Filters cards/devlogs/jams/topics,
   blocks banned pages, hides banned tag links, scrubs comments. Verifies game
   pages via the background worker (message). rules.js (CF) loads before this. */
(function () {
  "use strict";
  const classify = CF.classify;

  let cfg = {
    enabled: false, bannedTags: [], bannedKeywords: [],
    blockedIds: [], blockedCreators: [], allowedIds: [], blockedSlugs: [],
  };

  /* ---- hide-until-verified CSS injected immediately (before cards paint) ---- */
  (function injectHide() {
    const css =
      ".game_cell[data-game_id]:not([data-cf-ok]){display:none !important}" +
      ".cf-devrow:not([data-cf-ok]){display:none !important}" +
      ".jam:not([data-cf-ok]),.jam_cell:not([data-cf-ok]){display:none !important}";
    const put = () => {
      if (document.getElementById("cf-hide")) return true;
      const t = document.head || document.documentElement;
      if (!t) return false;
      const s = document.createElement("style");
      s.id = "cf-hide"; s.textContent = css; t.appendChild(s);
      return true;
    };
    if (put()) return;
    const o = new MutationObserver(() => { if (put()) o.disconnect(); });
    o.observe(document, { childList: true, subtree: true });
  })();

  const HID = "data-cf-hidden";
  const reveal = (el) => el.setAttribute("data-cf-ok", "1");
  const textOf = (r, s) => (r.querySelector(s)?.textContent || "").trim();
  const toSlug = (s) => s.toLowerCase().replace(/[\s_]+/g, "-");
  function slugBlocked(url) {
    const list = cfg.blockedSlugs || [];
    if (!url || !list.length) return false;
    const u = url.toLowerCase();
    return list.some((s) => s && u.includes(s.toLowerCase()));
  }
  function checkGame(url) {
    return new Promise((res) =>
      chrome.runtime.sendMessage({ type: "check-game", url }, (r) =>
        res(chrome.runtime.lastError ? null : r)
      )
    );
  }

  /* ---- storefront cards: reveal only after the game page is confirmed clean ---- */
  function checkOne(cell) {
    cell.setAttribute("data-cf-checked", "1");
    const c = {
      kind: "card",
      id: cell.getAttribute("data-game_id") || undefined,
      title: textOf(cell, ".game_title, .title, a.title"),
      author: textOf(cell, ".game_author, .author"),
      text: textOf(cell, ".game_text"),
      url: cell.querySelector("a.thumb_link, a.game_link, a.title")?.href,
    };
    if (classify(c, cfg).blocked || slugBlocked(c.url || "")) return; // banned → stay hidden
    if (!c.url) return; // can't verify → stay hidden (fail-closed)
    checkGame(c.url).then((r) => { if (r && r.blocked === false) reveal(cell); });
  }
  function filterCards() {
    if (!cfg.enabled) return;
    document
      .querySelectorAll(".game_cell[data-game_id]:not([data-cf-checked])")
      .forEach(checkOne);
  }

  /* ---- whole-page block (banned category/search/slug) ---- */
  function blockPage(reason) {
    document.documentElement.innerHTML =
      '<body style="background:#1b1733;color:#f4f1e8;font-family:sans-serif;display:flex;' +
      'align-items:center;justify-content:center;height:100vh;margin:0"><div style="text-align:center">' +
      '<h1 style="color:#ffc247">Hidden</h1><p>This page was blocked by the content filter.</p></div></body>';
    window.__cfBlocked = reason;
  }
  function filterBannedUrl() {
    const url = new URL(location.href);
    if (slugBlocked(location.href)) { blockPage("blocked-slug"); return true; }
    const m = url.pathname.toLowerCase().match(/\/(?:tag|genre)-([a-z0-9-]+)/);
    const q = url.searchParams.get("q") || "";
    if (m && cfg.bannedTags.map(toSlug).includes(m[1])) { blockPage("tag-page:" + m[1]); return true; }
    const probe = (m ? m[1].replace(/-/g, " ") : "") + " " + q;
    if (probe.trim() && classify({ kind: "card", title: probe }, cfg).blocked) {
      blockPage("banned-query"); return true;
    }
    return false;
  }

  /* ---- a single game page ---- */
  function filterGamePage() {
    if (!document.querySelector(".game_info_panel_widget, .game_info_panel")) return;
    const tags = Array.from(
      document.querySelectorAll(
        ".game_info_panel_widget a[href*='/tag-'], .game_info_panel_widget a[href*='tag='], .game_info_panel_widget a[href*='/genre-']"
      )
    ).map((a) => a.textContent?.trim() || "");
    const c = {
      kind: "game",
      title: textOf(document, "h1.game_title, .game_title"),
      tags,
      adultWarning: Boolean(document.querySelector(".content_warning_outer, .age_gate, .adult_content")),
      text: textOf(document, ".formatted_description, .game_description"),
    };
    if (classify(c, cfg).blocked || slugBlocked(location.href)) blockPage("game-page");
  }

  /* ---- comments ---- */
  function filterComments(root = document) {
    root.querySelectorAll(".community_post").forEach((post) => {
      if (post.getAttribute(HID)) return;
      const c = { kind: "comment", author: textOf(post, ".post_author, a.user_link"), text: textOf(post, ".post_body, .community_post_content") };
      if (classify(c, cfg).blocked) {
        post.setAttribute(HID, "1");
        const b = post.querySelector(".post_body, .community_post_content");
        if (b) b.textContent = "[comment hidden by content filter]";
      }
    });
  }

  /* ---- jams + community topics (keyword / slug on their text) ---- */
  function hideListRow(el) {
    let n = el;
    for (let i = 0; i < 5 && n.parentElement; i++) { if (n.parentElement.children.length >= 3) break; n = n.parentElement; }
    n.style.display = "none";
  }
  function filterTextRows(root = document) {
    root.querySelectorAll(".topic_title").forEach((el) => {
      if (el.getAttribute(HID)) return;
      el.setAttribute(HID, "1");
      const link = el.querySelector("a[href]") || el.closest("a");
      if (classify({ kind: "card", title: el.textContent || "" }, cfg).blocked || slugBlocked(link?.href || "")) hideListRow(el);
    });
  }

  /* ---- jams: hidden until confirmed clean (synchronous, no flash) ----
     Signal = title + short_text blurb + slug. NOT the jam page's rules body —
     that over-blocks responsible jams ("no NSFW" reads as NSFW). */
  function filterJams(root = document) {
    root.querySelectorAll(".jam, .jam_cell").forEach((el) => {
      if (el.getAttribute("data-cf-jam")) return;
      el.setAttribute("data-cf-jam", "1");
      const link = el.querySelector('a[href*="/jam/"]');
      const title = textOf(el, 'h3, .jam_title') || textOf(el, 'a[href*="/jam/"]');
      const blurb = textOf(el, ".short_text");
      const banned =
        classify({ kind: "card", title: title + " " + blurb }, cfg).blocked ||
        slugBlocked(link?.getAttribute("href") || "") ||
        slugBlocked(link?.href || "");
      if (!banned) reveal(el); // clean → show; banned stays hidden by CSS
    });
  }

  /* ---- devlogs: verified against their game (hidden until clean) ---- */
  function filterDevlogs(root = document) {
    root.querySelectorAll(".post_details").forEach((details) => {
      if (details.getAttribute(HID)) return;
      details.setAttribute(HID, "1");
      const row = details.parentElement || details;
      row.classList.add("cf-devrow");
      if (classify({ kind: "card", title: textOf(details, ".post_title") }, cfg).blocked) return;
      const link = row.querySelector('a[href*="/devlog/"]');
      const gameUrl = (link?.href || "").replace(/\/devlog\/.*$/, "");
      if (!gameUrl) { row.classList.remove("cf-devrow"); return; }
      if (slugBlocked(gameUrl)) return;
      checkGame(gameUrl).then((r) => { if (r && r.blocked === false) reveal(row); });
    });
  }

  /* ---- remove ONLY banned tag/genre links ---- */
  function hideBannedTagLinks(root = document) {
    root.querySelectorAll('a[href*="/tag-"], a[href*="/genre-"]').forEach((a) => {
      if (a.getAttribute(HID)) return;
      a.setAttribute(HID, "1");
      const m = a.href.match(/\/(?:tag|genre)-([a-z0-9-]+)/);
      if (!m) return;
      if (cfg.bannedTags.map(toSlug).includes(m[1]) || classify({ kind: "card", title: m[1].replace(/-/g, " ") }, cfg).blocked) a.style.display = "none";
    });
  }

  function runAll() {
    if (!cfg.enabled) return;
    if (filterBannedUrl()) return;
    filterCards();
    filterJams();
    filterComments();
    filterTextRows();
    filterDevlogs();
    hideBannedTagLinks();
    filterGamePage();
  }

  function boot() {
    runAll();
    new MutationObserver((muts) => {
      if (!cfg.enabled) return;
      let saw = false;
      muts.forEach((mm) => mm.addedNodes.forEach((n) => {
        if (n.nodeType !== 1) return;
        saw = true;
        filterComments(n); filterTextRows(n); filterDevlogs(n); hideBannedTagLinks(n);
      }));
      if (saw) { filterCards(); filterJams(); }
    }).observe(document.documentElement, { childList: true, subtree: true });
  }

  // on every page load, ask the worker to checksum GitHub and pull if different
  try { chrome.runtime.sendMessage({ type: "sync-now" }, () => void chrome.runtime.lastError); } catch {}

  // load config, then run
  chrome.storage.local.get("config", (r) => {
    if (r && r.config) cfg = r.config;
    if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", boot);
    else boot();
  });
  chrome.storage.onChanged.addListener((c) => { if (c.config) { cfg = c.config.newValue; runAll(); } });
})();
