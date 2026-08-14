#!/usr/bin/env bash
# Windows installer for the itch.io Content Filter.
# Run in Git Bash (or WSL) AS ADMINISTRATOR. It force-installs the extension via
# Chrome policy, which also enables free self-hosted auto-update. The student
# does nothing after this; Chrome installs + updates it on its own.
#
#   Right-click Git Bash -> "Run as administrator", then:  ./install.sh
set -euo pipefail

ID="innfmidphklblkkbhnhhpjkfplbomale"
URL="https://raw.githubusercontent.com/qershyahya/itch-filter/main/updates.xml"
ENTRY="$ID;$URL"
KEY='HKLM\SOFTWARE\Policies\Google\Chrome\ExtensionInstallForcelist'

command -v reg.exe >/dev/null 2>&1 || { echo "!! reg.exe not found. Run this in Git Bash or WSL on Windows."; exit 1; }

# elevation check: HKU\S-1-5-19 is only readable by an elevated process
if ! reg.exe query "HKU\\S-1-5-19" >/dev/null 2>&1; then
  echo "!! Not running as Administrator."
  echo "   Close this, right-click Git Bash -> 'Run as administrator', re-run ./install.sh"
  exit 1
fi

# already present?
if reg.exe query "$KEY" 2>/dev/null | grep -qi "$ID"; then
  echo "Already installed. Fully restart Chrome (or chrome://extensions -> Update) to apply."
  exit 0
fi

# pick the next free numeric slot so we don't clobber other forced extensions
idx=1
while reg.exe query "$KEY" /v "$idx" >/dev/null 2>&1; do idx=$((idx + 1)); done

reg.exe add "$KEY" /v "$idx" /t REG_SZ /d "$ENTRY" /f >/dev/null
echo "Added policy entry #$idx:"
reg.exe query "$KEY"

cat <<'DONE'

Done. Now:
  1. Fully quit and reopen Chrome (all windows).
  2. Check chrome://policy      -> ExtensionInstallForcelist should list the extension.
  3. Check chrome://extensions  -> "itch.io Content Filter", installed by administrator.
It will auto-update from GitHub from now on. No reinstall needed.

To remove it later (also as Administrator):
  reg.exe delete 'HKLM\SOFTWARE\Policies\Google\Chrome\ExtensionInstallForcelist' /f
DONE
