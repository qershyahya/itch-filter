# itch.io Content Filter — Chrome extension

Filters itch.io in regular Chrome: games, jams, devlogs, collections, community
topics, comments — plus a page-block for banned categories/searches and a manual
block-list. Same rules as the desktop-app version (61 tags / 599 keywords, tuned
for an Islamic students' environment).

## Install (one time)

1. Open Chrome → go to **`chrome://extensions`**
2. Turn on **Developer mode** (top-right toggle)
3. Click **Load unpacked** → select this folder (`itch-filter-extension`)
4. Done — the filter is now active on every itch.io page.

(To hand it to students' machines, copy this folder and repeat, or pack it into a
`.crx` from the same page.)

## Settings (PIN-protected)

Click the extension icon (or **Details → Extension options**):
- First time: **set a parent PIN**.
- After unlocking, edit the **banned tags**, **banned keywords**, **block-list**
  (URL words — jam slugs, creators, game slugs), **blocked creators**, and
  **allow-overrides**. Reload itch.io tabs to apply.

The lists come pre-loaded with the full preset. The block-list starts with
`spooktober` as an example — add any word that appears in a URL to block it
(e.g. a creator name or a specific jam/game slug).

## What it does

| Surface | Behaviour |
|---|---|
| Game cards | Hidden until the game's real page is fetched & confirmed clean (fail-closed, retries) |
| Game pages | Blocked outright on any banned tag/genre/keyword |
| Collections | Same as game cards |
| Devlogs | Verified against the underlying game; hidden if the game is banned |
| Comments | Scrubbed by keyword |
| Community topics / jams | Hidden by keyword on title, or by block-list |
| Category / search pages | Whole page blocked if the tag/genre/query is banned |
| Tag links | Only **banned** tag links removed; clean tags stay |
| Block-list | Any URL containing a listed word → page blocked & card hidden |

## How it's built

- `content.js` — runs on every itch.io page, does all the DOM filtering.
- `background.js` — fetches & classifies game/jam pages (cross-site fetch is
  allowed here, so no CORS problem), caches verdicts, owns the config.
- `rules.js` — the shared classification engine.
- `options.html/js` — the PIN-locked settings page.
- Config lives in `chrome.storage.local` (seeded from `defaultConfig.js` on install).

## Note on being logged out

Leave itch.io **logged out** in this Chrome — logged-out browsing already hides
adult content by default, which is a free extra layer on top of this filter.
