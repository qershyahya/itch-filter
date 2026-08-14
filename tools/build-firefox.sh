#!/usr/bin/env bash
# Build (and optionally sign) the Firefox add-on from the shared extension files.
# Unsigned build always works for local testing (about:debugging). Force-install
# via policies.json needs a SIGNED .xpi — Mozilla signing is free:
#   1. Create an addons.mozilla.org account, get API credentials at
#      https://addons.mozilla.org/developers/addon/api/key/
#   2. AMO_JWT_ISSUER=... AMO_JWT_SECRET=... ./build-firefox.sh
#   (needs `web-ext`:  npm i -g web-ext)
set -euo pipefail
cd "$(dirname "$0")/.."
EXT=itch-filter-extension
OUT=dist-firefox

rm -rf "$OUT"; mkdir -p "$OUT"
cp "$EXT"/*.js "$EXT"/*.html "$OUT"/
cp "$EXT/manifest.firefox.json" "$OUT/manifest.json"   # Firefox manifest becomes the manifest
( cd "$OUT" && zip -q -r -X ../itch-filter.unsigned.xpi . )
echo "built itch-filter.unsigned.xpi (for about:debugging testing)"

if [ -n "${AMO_JWT_ISSUER:-}" ] && [ -n "${AMO_JWT_SECRET:-}" ] && command -v web-ext >/dev/null 2>&1; then
  echo "signing via AMO (unlisted)…"
  web-ext sign --source-dir "$OUT" --channel unlisted \
    --api-key "$AMO_JWT_ISSUER" --api-secret "$AMO_JWT_SECRET" \
    --artifacts-dir "$OUT-signed"
  signed="$(ls -t "$OUT-signed"/*.xpi 2>/dev/null | head -1 || true)"
  if [ -n "$signed" ]; then cp -f "$signed" itch-filter.xpi; echo "signed -> itch-filter.xpi (push this to the repo)"; fi
else
  echo "No AMO creds (or web-ext missing) — skipped signing."
  echo "Force-install needs the signed itch-filter.xpi; see header for the free steps."
fi
