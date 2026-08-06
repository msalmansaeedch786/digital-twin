#!/usr/bin/env bash
#
# Renders frontend/public/twin-cover.png — the Open Graph card served as
# og:image / twitter:image from frontend/src/app/layout.js.
#
# Like the architecture diagram, this image is GENERATED, not drawn: edit
# scripts/cover.html, re-run this script, and commit the resulting PNG.
#
# The card uses the light-theme design tokens from
# frontend/src/app/globals.css (:root) so it matches the page it links to.
# Webfonts load from the Google Fonts CDN, so this needs network access.
#
# Output is 2400x1260 (a 2x render of the 1200x630 OG canvas), which is what
# LinkedIn, Slack, X and iMessage expect for a summary_large_image card.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="$REPO_ROOT/scripts/cover.html"
OUT="$REPO_ROOT/frontend/public/twin-cover.png"

CHROME="${CHROME:-/Applications/Google Chrome.app/Contents/MacOS/Google Chrome}"
if [ ! -x "$CHROME" ]; then
  echo "Chrome not found at: $CHROME" >&2
  echo "Set CHROME=/path/to/chrome and re-run." >&2
  exit 1
fi

# --virtual-time-budget lets the webfonts finish loading before the snapshot;
# without it Chrome can screenshot mid-load and fall back to a system font.
"$CHROME" \
  --headless \
  --disable-gpu \
  --hide-scrollbars \
  --force-device-scale-factor=2 \
  --window-size=1200,630 \
  --virtual-time-budget=8000 \
  --screenshot="$OUT" \
  "file://$SRC"

echo "Wrote $OUT"
