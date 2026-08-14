#!/usr/bin/env bash
# Free code auto-update pipeline: bump version, pack a signed .crx with the SAME
# key (stable ID), write updates.xml, refresh policy files. Then `git push` the
# dist/ folder — force-installed Chromes pull the new version within a few hours.
#
#   ./release.sh            # auto-bumps the patch version (1.0.0 -> 1.0.1)
#   ./release.sh 1.4.0      # set an explicit version
set -euo pipefail
cd "$(dirname "$0")/.."                       # -> /home/yahya
ROOT="$PWD"; EXT="$ROOT/itch-filter-extension"; TOOLS="$ROOT/itch-filter-tools"; DIST="$ROOT/dist"
KEY="$TOOLS/signing-key.pem"; ID="$(cat "$TOOLS/extension-id.txt")"
source "$TOOLS/release.conf"
[ "$RAW_BASE" = "https://raw.githubusercontent.com/USER/REPO/main" ] && { echo "!! Edit RAW_BASE in itch-filter-tools/release.conf first."; exit 1; }

# version: arg, else patch-bump current manifest version
cur=$(node -e 'process.stdout.write(require("'"$EXT"'/manifest.json").version)')
if [ $# -ge 1 ]; then ver="$1"; else IFS=. read -r a b c <<<"$cur"; ver="$a.$b.$((c+1))"; fi
node -e 'const f="'"$EXT"'/manifest.json",j=require(f);j.version="'"$ver"'";j.update_url="'"$RAW_BASE"'/updates.xml";require("fs").writeFileSync(f,JSON.stringify(j,null,2)+"\n")'
echo "version $cur -> $ver"

# pack signed crx with the stable key
rm -f "$ROOT/itch-filter-extension.crx"
DISPLAY=${DISPLAY:-:1} google-chrome --pack-extension="$EXT" --pack-extension-key="$KEY" --no-sandbox >/dev/null 2>&1 || true
[ -f "$ROOT/itch-filter-extension.crx" ] || { echo "!! pack failed"; exit 1; }

mkdir -p "$DIST"
mv -f "$ROOT/itch-filter-extension.crx" "$DIST/itch-filter-extension.crx"
cat > "$DIST/updates.xml" <<XML
<?xml version='1.0' encoding='UTF-8'?>
<gupdate xmlns='http://www.google.com/update2/response' protocol='2.0'>
  <app appid='$ID'>
    <updatecheck codebase='$RAW_BASE/itch-filter-extension.crx' version='$ver' />
  </app>
</gupdate>
XML
# also keep the hostable list-config fresh in dist (optional single source)
cp -f "$TOOLS/filter-config.json" "$DIST/filter-config.json" 2>/dev/null || true

# refresh policy files with real ID + url
printf '{\n  "ExtensionInstallForcelist": [\n    "%s;%s/updates.xml"\n  ]\n}\n' "$ID" "$RAW_BASE" > "$TOOLS/policies/linux/itch-filter.json"
cat > "$TOOLS/policies/windows/itch-filter.reg" <<REG
Windows Registry Editor Version 5.00

[HKEY_LOCAL_MACHINE\\SOFTWARE\\Policies\\Google\\Chrome\\ExtensionInstallForcelist]
"1"="$ID;$RAW_BASE/updates.xml"
REG

echo "OK. Now: cd $DIST && git add -A && git commit -m 'release $ver' && git push"