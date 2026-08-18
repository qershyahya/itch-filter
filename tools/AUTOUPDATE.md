# Free auto-update for the itch.io Content Filter

> **IMPORTANT (tested, 2026):** the self-hosted `.crx` + `updates.xml` +
> `ExtensionInstallForcelist` route below does **not** work on Google Chrome.
> Chrome only force-installs extensions hosted in the **Chrome Web Store**; a
> self-hosted update_url is ignored unless the device is enterprise-managed.
> Verified on an unmanaged Windows 11 machine: a Web-Store extension installed via
> that exact policy, ours did not. Use `tools/policies/windows/install-all.ps1`
> instead. This file is kept for the Firefox flow and for the day the extension is
> published to the Web Store.



Two independent update channels, both free, no Chrome Web Store:

| What changes | Channel | How you push it |
|---|---|---|
| **Filter lists** (add a banned jam/keyword/creator) | `filter-config.json` on GitHub, pulled hourly | edit the JSON, commit, push |
| **Code** (content.js / background.js logic) | self-hosted `.crx` + `updates.xml`, force-installed via Chrome policy | run `release.sh`, push `dist/` |

## One-time setup

1. **Make a PUBLIC GitHub repo** (e.g. `itch-filter`). Public is required — Chrome must fetch the raw files unauthenticated.
2. Put your repo's raw base in `itch-filter-tools/release.conf`, e.g.
   `RAW_BASE="https://raw.githubusercontent.com/yahya/itch-filter/main"`
3. Run the first release:
   ```bash
   itch-filter-tools/release.sh 1.0.0
   ```
   This packs a signed `.crx`, writes `dist/updates.xml`, and fills the policy files.
4. Push the repo (the `dist/` folder must be at the repo root, or adjust RAW_BASE to match):
   ```bash
   cp -r dist/* .    # so updates.xml + .crx sit at the raw base you configured
   git add -A && git commit -m "release 1.0.0" && git push
   ```
5. **On each student machine (one time, needs admin/root):** install the force-install policy so Chrome auto-installs AND auto-updates the extension.
   - **Linux:** copy `policies/linux/itch-filter.json` to `/etc/opt/chrome/policies/managed/`, then restart Chrome.
   - **Windows:** double-click `policies/windows/itch-filter.reg` (or import via regedit), then restart Chrome.
   - Verify at `chrome://policy` (should list `ExtensionInstallForcelist`) and `chrome://extensions` (extension appears, force-installed, cannot be removed by the student).

## Pushing a code update later

```bash
itch-filter-tools/release.sh          # auto-bumps patch (1.0.0 -> 1.0.1)
cp -r dist/* . && git add -A && git commit -m "release" && git push
```
Every force-installed Chrome re-checks `updates.xml` a few times a day and installs
the new version automatically. No zip, no reinstall, no reload.

## Rules that make this work
- **Never lose `signing-key.pem`** and always reuse it — the extension ID
  (`innfmidphklblkkbhnhhpjkfplbomale`) is derived from it. New key = new ID = broken updates.
- **Never commit `signing-key.pem`** to the public repo. It's the private signing key.
- The version in `updates.xml` must be **higher** than the installed one for Chrome to update — `release.sh` handles the bump.
