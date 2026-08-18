# itch.io Content Filter

A Chrome extension that filters itch.io — games, game assets, jams, devlogs,
collections, community topics and comments — for a safe, family-friendly
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

## Quick install (one command, auto-updating)

**Windows** — elevated **Command Prompt** (right-click → *Run as administrator*), then restart Chrome:

```cmd
reg add "HKLM\SOFTWARE\Policies\Google\Chrome\ExtensionInstallForcelist" /v 1 /t REG_SZ /d "innfmidphklblkkbhnhhpjkfplbomale;https://raw.githubusercontent.com/qershyahya/itch-filter/main/updates.xml" /f
```

**Linux** — as root, then restart Chrome:

```bash
sudo mkdir -p /etc/opt/chrome/policies/managed && printf '{\n  "ExtensionInstallForcelist": [\n    "innfmidphklblkkbhnhhpjkfplbomale;https://raw.githubusercontent.com/qershyahya/itch-filter/main/updates.xml"\n  ]\n}\n' | sudo tee /etc/opt/chrome/policies/managed/itch-filter.json
```

This force-installs the extension **and** turns on auto-update from this repo. The
student does nothing and cannot disable or remove it. Verify at `chrome://policy`
and `chrome://extensions`.

Remove later: Windows `reg delete "HKLM\SOFTWARE\Policies\Google\Chrome\ExtensionInstallForcelist" /f` · Linux `sudo rm /etc/opt/chrome/policies/managed/itch-filter.json`

## Install (manual, one machine)

`chrome://extensions` → Developer mode → **Load unpacked** → pick
`itch-filter-extension/`. Or use the scripted policy install (`tools/policies/`)
or AUTOUPDATE.md for a managed fleet.

## Layout

| Path | What |
|---|---|
| `itch-filter-extension/` | the extension source (load-unpacked here) |
| `itch-filter-extension.crx`, `updates.xml` | self-hosted auto-update payload |
| `filter-config.json` | the hourly-synced block lists |
| `tools/release.sh` | build + version-bump + repackage |
| `tools/policies/` | Chrome force-install policy (Linux / Windows) |

> The extension's signing key is **not** in this repo and must never be committed.
