#!/usr/bin/env bash
#
# Renders scripts/onepager.html to a 4-page landscape PDF, sized for LinkedIn's
# document carousel (it renders an uploaded PDF as swipeable slides in-feed).
#
# Like the architecture diagram and the OG cover, this is GENERATED, not drawn:
# edit scripts/onepager.html and re-run this script.
#
# Pages are 1280x720 CSS px (13.333in x 7.5in at 96dpi) — the standard 16:9
# slide. Webfonts load from the Google Fonts CDN, so this needs network access.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="$REPO_ROOT/scripts/onepager.html"
OUT="${1:-$REPO_ROOT/digital-twin-onepager.pdf}"

CHROME="${CHROME:-/Applications/Google Chrome.app/Contents/MacOS/Google Chrome}"
if [ ! -x "$CHROME" ]; then
  echo "Chrome not found at: $CHROME" >&2
  echo "Set CHROME=/path/to/chrome and re-run." >&2
  exit 1
fi

# --no-pdf-header-footer strips Chrome's default date/URL furniture.
# --virtual-time-budget lets the webfonts finish loading before printing.
"$CHROME" \
  --headless \
  --disable-gpu \
  --no-pdf-header-footer \
  --print-to-pdf-no-header \
  --virtual-time-budget=8000 \
  --print-to-pdf="$OUT" \
  "file://$SRC"

echo "Wrote $OUT"
