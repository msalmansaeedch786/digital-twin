#!/usr/bin/env bash
#
# Renders scripts/stories.html to one 1080x1920 PNG per story frame, ready to
# upload to Instagram Stories.
#
# Each frame is a .story block in the HTML; this hides all but one and takes a
# screenshot, so the frame count follows the markup automatically.
#
# Content sits inside a 250px top/bottom inset because Instagram's own UI
# (profile row, reply bar, link sticker) overlays those bands.
#
# Webfonts load from the Google Fonts CDN, so this needs network access.
# --allow-file-access-from-files lets the architecture frame load the PNG.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="$REPO_ROOT/scripts/stories.html"
OUT_DIR="${1:-$REPO_ROOT/instagram-stories}"

CHROME="${CHROME:-/Applications/Google Chrome.app/Contents/MacOS/Google Chrome}"
if [ ! -x "$CHROME" ]; then
  echo "Chrome not found at: $CHROME" >&2
  echo "Set CHROME=/path/to/chrome and re-run." >&2
  exit 1
fi

mkdir -p "$OUT_DIR"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

COUNT="$(grep -c '<div class="story">' "$SRC")"
echo "Rendering $COUNT story frames x 2 themes -> $OUT_DIR"

for theme in dark light; do
  for n in $(seq 1 "$COUNT"); do
    # Hide every frame but the nth, keeping the markup as the single source.
    # The temp copy lives outside scripts/, so the relative <img> path is
    # rewritten to an absolute one or the architecture frame renders empty.
    sed -e "s|</head>|<style>.story{display:none}.story:nth-of-type($n){display:block}</style></head>|" \
        -e "s|\.\./frontend/public/|file://$REPO_ROOT/frontend/public/|g" \
      "$SRC" > "$TMP/story$n-$theme.html"

    # Dark is the stylesheet default; the light set adds the class that flips
    # every token. Done here rather than in the markup so both themes stay a
    # single source of truth.
    if [ "$theme" = "light" ]; then
      sed -i '' 's|<div class="story">|<div class="story light">|g' "$TMP/story$n-$theme.html"
    fi

    "$CHROME" \
      --headless \
      --disable-gpu \
      --hide-scrollbars \
      --allow-file-access-from-files \
      --window-size=1080,1920 \
      --virtual-time-budget=10000 \
      --screenshot="$OUT_DIR/story-$n-$theme.png" \
      "file://$TMP/story$n-$theme.html" 2>/dev/null

    echo "  story-$n-$theme.png"
  done
done

echo "Done."
