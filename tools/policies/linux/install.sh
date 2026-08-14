#!/usr/bin/env bash
# Linux installer for the itch.io Content Filter.
# Run as root:  sudo ./install.sh
# Force-installs the extension via Chrome managed policy, which also enables free
# self-hosted auto-update from GitHub. The student does nothing after this and
# cannot disable or remove it.
set -euo pipefail

ID="innfmidphklblkkbhnhhpjkfplbomale"
URL="https://raw.githubusercontent.com/qershyahya/itch-filter/main/updates.xml"

[ "$(id -u)" -eq 0 ] || { echo "!! Run as root:  sudo ./install.sh"; exit 1; }

write_policy() {
  local dir="$1"
  mkdir -p "$dir"
  printf '{\n  "ExtensionInstallForcelist": [\n    "%s;%s"\n  ]\n}\n' "$ID" "$URL" > "$dir/itch-filter.json"
  echo "wrote $dir/itch-filter.json"
}

# Google Chrome (always). Uses a dedicated file, so other managed policies are untouched.
write_policy /etc/opt/chrome/policies/managed
# Chromium too, if present.
if command -v chromium >/dev/null 2>&1 || command -v chromium-browser >/dev/null 2>&1; then
  write_policy /etc/chromium/policies/managed
fi

cat <<'DONE'

Done. Now:
  1. Fully quit and reopen Chrome.
  2. chrome://policy      -> ExtensionInstallForcelist should list the extension (Reload policies if needed).
  3. chrome://extensions  -> "itch.io Content Filter", installed by administrator.
It auto-updates from GitHub from now on. No reinstall needed.

To remove later (as root):
  rm -f /etc/opt/chrome/policies/managed/itch-filter.json /etc/chromium/policies/managed/itch-filter.json
DONE
