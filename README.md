# itch.io Content Filter

A Chrome extension that filters itch.io — games, game assets, jams, devlogs,
collections, community topics and comments — for a safe (Islamic students')
environment. Blocks sexual/adult, LGBTQ, dating/romance, horror/violence,
gambling, drugs/alcohol, occult and profanity across the site.

## Two free update channels (no Chrome Web Store)

- **Filter lists** — the extension pulls `filter-config.json` from this repo every
  hour. Add a banned jam/keyword/creator by editing that file; every machine
  follows within the hour.
- **Code** — a self-hosted, auto-updating `.crx` (`itch-filter-extension.crx` +
  `updates.xml`) force-installed via a Chrome policy. Push a new version with
  `tools/release.sh`; installed browsers update themselves.

Full setup: **[tools/AUTOUPDATE.md](tools/AUTOUPDATE.md)**.

## Install (manual, one machine)

`chrome://extensions` → Developer mode → **Load unpacked** → pick
`itch-filter-extension/`. Or use the policy-based install in AUTOUPDATE.md for a
managed fleet.

## Layout

| Path | What |
|---|---|
| `itch-filter-extension/` | the extension source (load-unpacked here) |
| `itch-filter-extension.crx`, `updates.xml` | self-hosted auto-update payload |
| `filter-config.json` | the hourly-synced block lists |
| `tools/release.sh` | build + version-bump + repackage |
| `tools/policies/` | Chrome force-install policy (Linux / Windows) |

> The extension's signing key is **not** in this repo and must never be committed.
