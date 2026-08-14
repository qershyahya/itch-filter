#!/usr/bin/env node
// End-to-end verifier: launches Chrome with the REAL extension loaded, opens a
// page, and checks the actual rendered DOM over CDP. No dependencies (Node 24
// globals: fetch, WebSocket). Fresh --user-data-dir each run => always tests the
// current on-disk code, so there is no "reload the extension" step to forget.
import { spawn } from "node:child_process";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

const EXT = "/home/yahya/itch-filter-extension";
const URLS = process.argv.slice(2);
if (!URLS.length) URLS.push("https://itch.io/jams");
const PORT = 9333;
const profile = mkdtempSync(join(tmpdir(), "cf-verify-"));

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

const chrome = spawn("google-chrome", [
  `--load-extension=${EXT}`,
  `--disable-extensions-except=${EXT}`,
  `--user-data-dir=${profile}`,
  `--remote-debugging-port=${PORT}`,
  "--no-first-run", "--no-default-browser-check", "--disable-background-timer-throttling",
  "about:blank",
], { stdio: "ignore" });

let ws;
function rpc(method, params = {}) {
  return new Promise((res, rej) => {
    const id = rpc._id = (rpc._id || 0) + 1;
    const onMsg = (e) => {
      const m = JSON.parse(e.data);
      if (m.id === id) { ws.removeEventListener("message", onMsg); m.error ? rej(new Error(m.error.message)) : res(m.result); }
    };
    ws.addEventListener("message", onMsg);
    ws.send(JSON.stringify({ id, method, params }));
  });
}
async function evalIn(expr) {
  const r = await rpc("Runtime.evaluate", { expression: expr, returnByValue: true, awaitPromise: true });
  if (r.exceptionDetails) throw new Error(r.exceptionDetails.text);
  return r.result.value;
}

async function targets() {
  const r = await fetch(`http://127.0.0.1:${PORT}/json`).then((x) => x.json()).catch(() => []);
  return r.filter((t) => t.type === "page");
}

async function connectPage(url) {
  // open the url in the existing about:blank page target
  let pages = [];
  for (let i = 0; i < 40 && !pages.length; i++) { pages = await targets(); if (!pages.length) await sleep(250); }
  const page = pages[0];
  ws = new WebSocket(page.webSocketDebuggerUrl);
  await new Promise((r) => ws.addEventListener("open", r, { once: true }));
  await rpc("Page.enable"); await rpc("Runtime.enable");
  await rpc("Page.navigate", { url });
  await sleep(4500); // load + let the extension's async config + filter settle
}

const CHECK = `(() => {
  const jams = [...document.querySelectorAll('.jam, .jam_cell')];
  const vis = (el) => el.offsetParent !== null;
  const spooky = [...document.querySelectorAll('a[href*="spooktober"]')].map(a => vis(a.closest('.jam,.jam_cell')||a));
  return {
    total: jams.length,
    visible: jams.filter(vis).length,
    hidden: jams.filter(e => !vis(e)).length,
    spooktoberEls: spooky.length,
    spooktoberVisible: spooky.filter(Boolean).length,
    sampleVisibleTitles: jams.filter(vis).slice(0,5).map(j => (j.querySelector('h3, .jam_title, a[href*="/jam/"]')?.textContent||'').trim().slice(0,40)),
  };
})()`;

(async () => {
  try {
    for (const url of URLS) {
      await connectPage(url);
      // retry the check a few times in case the extension is still settling
      let r;
      for (let i = 0; i < 6; i++) { r = await evalIn(CHECK); if (r.total && r.spooktoberVisible === 0) break; await sleep(800); r = await evalIn(CHECK); }
      const pass = r.total > 0 && r.visible > 0 && r.spooktoberVisible === 0;
      console.log(`\n${url}`);
      console.log(JSON.stringify(r, null, 2));
      console.log(pass ? "PASS ✅ (jams present, clean ones visible, spooktober hidden)"
                       : "FAIL ❌ (spooktober visible OR nothing rendered)");
      if (ws) { ws.close(); ws = null; }
    }
  } catch (e) {
    console.error("ERROR:", e.message);
  } finally {
    chrome.kill("SIGKILL");
    try { rmSync(profile, { recursive: true, force: true }); } catch {}
    process.exit(0);
  }
})();
