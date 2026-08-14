#!/usr/bin/env bash
# Cross-platform, multi-browser installer for the itch.io Content Filter.
# Runs on Linux, macOS, and Windows (via Git Bash / WSL).
#
#   Firefox   -> force-installed via policies.json (needs the signed .xpi; enforced, no "managed" required)
#   Chromium  -> auto-loaded via --load-extension on each browser's launcher (deterrent; an admin can remove the flag)
#   Safari    -> can't be installed free; prints the macOS Screen Time block steps instead
#
# It downloads the current extension from GitHub, so re-running always installs the latest.
set -euo pipefail

REPO="qershyahya/itch-filter"
BRANCH="main"
GECKO_ID="itch-filter@qershyahya"
XPI_URL="https://raw.githubusercontent.com/$REPO/$BRANCH/itch-filter.xpi"
EXTDIR="$HOME/.itch-filter/extension"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

say() { printf '\n=== %s ===\n' "$1"; }
have() { command -v "$1" >/dev/null 2>&1; }

case "$(uname -s)" in
  Linux*)  OS=linux ;;
  Darwin*) OS=macos ;;
  MINGW*|MSYS*|CYGWIN*) OS=windows ;;
  *) echo "Unsupported OS: $(uname -s)"; exit 1 ;;
esac
echo "OS: $OS"

# ---- fetch the extension (Chromium load-unpacked target) ----
fetch_extension() {
  say "Downloading extension"
  local zip="$TMP/repo.zip"
  curl -fsSL "https://github.com/$REPO/archive/refs/heads/$BRANCH.zip" -o "$zip"
  ( cd "$TMP" && unzip -q repo.zip )
  mkdir -p "$EXTDIR"
  cp -f "$TMP/itch-filter-$BRANCH/itch-filter-extension/"* "$EXTDIR/"
  echo "Extension -> $EXTDIR"
}

# ---- Firefox: drop a policies.json that force-installs the signed xpi ----
firefox_policy_json() {
  cat <<JSON
{
  "policies": {
    "ExtensionSettings": {
      "$GECKO_ID": {
        "installation_mode": "force_installed",
        "install_url": "$XPI_URL"
      }
    }
  }
}
JSON
}
install_firefox() {
  say "Firefox"
  local wrote=0 dirs=()
  case "$OS" in
    linux)
      dirs=(/etc/firefox/policies /usr/lib/firefox/distribution /usr/lib64/firefox/distribution /opt/firefox/distribution)
      ;;
    macos)
      dirs=("/Applications/Firefox.app/Contents/Resources/distribution")
      ;;
    windows)
      dirs=("/c/Program Files/Mozilla Firefox/distribution" "/c/Program Files (x86)/Mozilla Firefox/distribution")
      ;;
  esac
  for d in "${dirs[@]}"; do
    local parent; parent="$(dirname "$d")"
    [ -d "$parent" ] || continue                 # only where Firefox actually lives (or /etc)
    if mkdir -p "$d" 2>/dev/null; then
      local f="$d/policies.json"
      [ "$(basename "$d")" = "policies" ] || f="$d/policies.json"
      if firefox_policy_json > "$f" 2>/dev/null; then echo "wrote $f"; wrote=1; fi
    fi
  done
  if [ "$wrote" = 0 ]; then echo "Firefox not found (or no permission) — skipped."; else
    echo "Firefox will force-install the extension on next launch."; fi
}

# ---- Chromium: add --load-extension to each browser's launcher ----
LOAD_FLAG="--load-extension=$EXTDIR"

# bash-3.2 safe (macOS): "desktop-basenames" per Chromium browser
CHROMIUM_LINUX="google-chrome google-chrome-stable chromium chromium-browser microsoft-edge microsoft-edge-stable brave-browser opera vivaldi-stable vivaldi"
# macOS .app names
CHROMIUM_MAC="Google Chrome|Microsoft Edge|Brave Browser|Opera|Vivaldi|Chromium"

install_chromium_linux() {
  local userapps="$HOME/.local/share/applications"; mkdir -p "$userapps"
  local base src d dst
  for base in $CHROMIUM_LINUX; do
    src=""
    for d in /usr/share/applications /var/lib/snapd/desktop/applications; do
      [ -f "$d/$base.desktop" ] && { src="$d/$base.desktop"; break; }
    done
    [ -n "$src" ] || continue
    dst="$userapps/$base.desktop"
    cp -f "$src" "$dst"
    # inject the flag into each Exec= line once
    if ! grep -q -- "$LOAD_FLAG" "$dst"; then
      sed -i.bak -E "s@^(Exec=[^ ]+)@\1 $LOAD_FLAG@" "$dst" && rm -f "$dst.bak"
    fi
    echo "$base: patched launcher -> $dst"
  done
  echo "(Chromium browsers load the filter when started from the app menu.)"
}

install_chromium_macos() {
  local wrapdir="$HOME/Applications/itch-filter-launchers"; mkdir -p "$wrapdir"
  local OLDIFS="$IFS"; IFS='|'
  local appname
  for appname in $CHROMIUM_MAC; do
    IFS="$OLDIFS"
    local app="/Applications/$appname.app"
    [ -d "$app" ] || { IFS='|'; continue; }
    local w="$wrapdir/$appname (filtered).command"
    printf '#!/usr/bin/env bash\nopen -na "%s" --args %s\n' "$app" "$LOAD_FLAG" > "$w"
    chmod +x "$w"
    echo "$appname: created filtered launcher -> $w"
    IFS='|'
  done
  IFS="$OLDIFS"
  echo "NOTE (macOS): Chromium can't persist the flag from the Dock. Use the"
  echo "'(filtered)' launchers in ~/Applications/itch-filter-launchers (or swap"
  echo "them into the Dock). Firefox above is fully enforced."
}

install_chromium_windows() {
  # patch Start-Menu/Desktop .lnk shortcuts via PowerShell
  have powershell.exe || { echo "powershell.exe not found — skipping Chromium shortcut patch."; return; }
  powershell.exe -NoProfile -Command "
    \$flag='$LOAD_FLAG'
    \$names='chrome','msedge','brave','opera','launcher','vivaldi'
    \$roots=@(\$env:APPDATA+'\Microsoft\Windows\Start Menu\Programs', \$env:ProgramData+'\Microsoft\Windows\Start Menu\Programs', \$env:USERPROFILE+'\Desktop')
    \$sh=New-Object -ComObject WScript.Shell
    foreach(\$r in \$roots){ if(!(Test-Path \$r)){continue}
      Get-ChildItem -Path \$r -Recurse -Filter *.lnk -ErrorAction SilentlyContinue | ForEach-Object {
        \$lnk=\$sh.CreateShortcut(\$_.FullName)
        \$t=[IO.Path]::GetFileNameWithoutExtension(\$lnk.TargetPath).ToLower()
        if((\$names -contains \$t) -and (\$lnk.Arguments -notlike '*--load-extension*')){
          \$lnk.Arguments=(\$lnk.Arguments+' '+\$flag).Trim(); \$lnk.Save()
          Write-Host ('patched: '+\$_.FullName)
        }
      }
    }" 2>/dev/null || echo "(shortcut patch had issues; Firefox path is unaffected)"
  echo "(Chromium browsers load the filter when started from a patched shortcut.)"
}

# ---- Safari (macOS only): can't install free ----
safari_note() {
  [ "$OS" = macos ] || return 0
  if [ -d "/Applications/Safari.app" ]; then
    say "Safari"
    cat <<'TXT'
Safari can't be installed for free (needs an Apple Developer ID, $99/yr).
Free alternative — block itch.io in Safari via Screen Time:
  System Settings > Screen Time > Content & Privacy > Content Restrictions >
  Web Content > Limit Adult Websites > Restricted list > add itch.io
Set a Screen Time passcode so it can't be changed casually.
TXT
  fi
}

# ---- run ----
fetch_extension
install_firefox
say "Chromium browsers"
case "$OS" in
  linux) install_chromium_linux ;;
  macos) install_chromium_macos ;;
  windows) install_chromium_windows ;;
esac
safari_note

say "Done"
echo "Restart any open browsers to apply."
echo "Reminder: Chromium loading here is a deterrent (an admin can remove the"
echo "flag). Firefox is enforced. Hard lockdown on Chromium still needs CBCM."
