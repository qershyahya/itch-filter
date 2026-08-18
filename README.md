# itch.io Safeguard Filter

A browser extension that filters itch.io - games, game assets, jams and their
submissions, devlogs, collections, community topics, comments and tag links -
for a safe, family-friendly environment. Blocks sexual/adult, LGBTQ,
dating/romance, horror/violence, gambling, drugs/alcohol, occult and profanity.

Content is verified **before** it is displayed (hide-until-checked, fail-closed),
so nothing appears and then vanishes, and a card you can see is a page you can open.

---

## Install

### Windows - one script, all browsers

Run in an **elevated PowerShell** (right-click PowerShell -> *Run as administrator*).
No clone needed - this downloads and runs the current script:

```powershell
$f="$env:TEMP\install-all.ps1"; irm https://raw.githubusercontent.com/qershyahya/itch-filter/main/tools/policies/windows/install-all.ps1 -OutFile $f; powershell -ExecutionPolicy Bypass -File $f
```

(If you cloned the repo, `powershell -ExecutionPolicy Bypass -File tools\policies\windows\install-all.ps1` works from the repo root.)

It detects Firefox / Chrome / Edge / Opera, asks which to install into
(**press Enter = all**), downloads the latest extension from this repo, installs
it, opens an onboarding page, and finishes with a **PASS/FAIL check per browser**.

Options:

```powershell
install-all.ps1 -Browsers all            # no menu, everything detected
install-all.ps1 -Browsers firefox,edge   # only these
install-all.ps1 -Quiet                   # unattended, all detected
```

Verify at any time (no admin needed) - exit code 0 = all protected:

```powershell
$f="$env:TEMP\verify-install.ps1"; irm https://raw.githubusercontent.com/qershyahya/itch-filter/main/tools/policies/windows/verify-install.ps1 -OutFile $f; powershell -ExecutionPolicy Bypass -File $f
```

Remove everything (elevated):

```powershell
$f="$env:TEMP\uninstall-all.ps1"; irm https://raw.githubusercontent.com/qershyahya/itch-filter/main/tools/policies/windows/uninstall-all.ps1 -OutFile $f; powershell -ExecutionPolicy Bypass -File $f
```

### Linux / macOS

```bash
sudo tools/install-all.sh
```

Force-installs into Firefox and wires the extension into any Chromium browser it finds.

### Firefox only (any OS, manual)

Download **[itch-filter.xpi](itch-filter.xpi)**, then Firefox ->
`about:addons` -> gear icon -> **Install Add-on From File**. It is
Mozilla-signed, so it installs without warnings.

---

## What each browser actually gets

This is the honest picture - the browsers differ, and it matters.

| Browser | How it installs | Can the user remove it? |
|---|---|---|
| **Firefox** | Force-installed via `distribution/policies.json` | **No - enforced** |
| **Edge, Opera** | `--load-extension` added to their shortcuts | Yes |
| **Chrome** | **Guided manual step** (5 clicks, the script walks you through it) | Yes |

**Why Chrome is manual.** Google Chrome refuses every automated install of a
self-hosted extension - `--load-extension` is ignored outright
(*"not allowed in Google Chrome"*), external-registry `.crx` installs are blocked,
and `ExtensionInstallForcelist` only accepts **Chrome Web Store**-hosted
extensions. All three were tested and confirmed. Manual "Load unpacked" is the
only method that persists without re-injecting on every launch, so the installer
opens the folder and `chrome://extensions` for you and waits.

> Publishing to the Chrome Web Store (a one-time $5 developer fee) would make the
> single-line `ExtensionInstallForcelist` registry command work on Chrome, Edge and
> Opera - installed automatically and **not removable**.

---

## Settings and central control

Settings are protected by a **preset secret key** (PBKDF2-SHA256, salted). There is
no "create a PIN" step, so nobody can claim the settings by opening the page first.

Open them via the extension icon -> **Administrator settings**, or right-click the
icon -> **Options**. The locked screen only offers: enter key, check for updates,
and support contacts.

**GitHub is the single source of truth.** The extension re-fetches
[`filter-config.json`](filter-config.json) on startup, on every itch.io page load
(throttled) and hourly, compares a SHA-256 checksum, and pulls when it differs -
**re-applying the central lists over any local edit**. To change what is blocked,
edit that file here; every machine follows. If GitHub is unreachable the last known
lists are kept, so blocking never silently switches off.

Blocked pages show a **Request review** button that submits the URL to a Google
Form you configure (`reviewUrl` / `reviewEntry`).

---

## Updating

- **Block lists** - edit `filter-config.json`, commit, push. No reinstall.
- **Extension code** - `tools/release.sh` (bumps version, rebuilds `.crx` + `updates.xml`),
  then push. Re-running the installer on a machine pulls the newest code.
- **Firefox add-on** - `tools/build-firefox.sh` builds the `.xpi`; sign it free via
  addons.mozilla.org (unlisted) and replace `itch-filter.xpi`.

See **[tools/AUTOUPDATE.md](tools/AUTOUPDATE.md)** for the full release flow.

---

## Layout

| Path | What |
|---|---|
| `itch-filter-extension/` | extension source (this is the load-unpacked folder) |
| `itch-filter.xpi` | Mozilla-signed Firefox add-on |
| `itch-filter-extension.crx`, `updates.xml` | self-hosted update payload |
| `filter-config.json` | the centrally-synced block lists |
| `tools/policies/windows/install-all.ps1` | Windows installer (all browsers) |
| `tools/policies/windows/verify-install.ps1` | verify what is actually loaded |
| `tools/policies/windows/uninstall-all.ps1` | remove everything |
| `tools/install-all.sh` | Linux / macOS installer |
| `tools/release.sh`, `tools/build-firefox.sh` | build + release |

> The extension signing key is **not** in this repo and must never be committed.

## Support

+20 110 119 6911 - qershyahya@gmail.com
