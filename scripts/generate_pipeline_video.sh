#!/usr/bin/env bash
#
# Renders scripts/pipeline.html to an MP4 explaining what happens between a
# question and an answer: API Gateway, Titan v2 embedding, pgvector retrieval,
# Nova Lite generation.
#
# The page draws itself purely from a ?t=<seconds> parameter, so each frame is
# a fresh headless screenshot at a fixed timestamp. That makes the render
# deterministic and reproducible, unlike screen-recording a live animation.
#
# Output is 1080x1920 (Instagram Stories / Reels). For a landscape cut, change
# WIDTH/HEIGHT and the .stage-canvas size in the HTML together.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# Override to render a different animation, e.g.
#   SRC_HTML=scripts/journey.html DURATION=15.6 ./scripts/generate_pipeline_video.sh out.mp4
SRC="${SRC_HTML:-$REPO_ROOT/scripts/pipeline.html}"
OUT="${1:-$REPO_ROOT/pipeline-explainer.mp4}"

FPS=20
DURATION="${DURATION:-14.6}"
WIDTH=1080
HEIGHT=1920
JOBS=4          # parallel Chrome instances; frames are independent

CHROME="${CHROME:-/Applications/Google Chrome.app/Contents/MacOS/Google Chrome}"
if [ ! -x "$CHROME" ]; then
  echo "Chrome not found at: $CHROME" >&2; exit 1
fi
if ! command -v ffmpeg >/dev/null 2>&1; then
  echo "ffmpeg not found. brew install ffmpeg" >&2; exit 1
fi

FRAMES="$(mktemp -d)"
trap 'rm -rf "$FRAMES"' EXIT

TOTAL=$(python3 -c "print(int($FPS * $DURATION))")
echo "Rendering $TOTAL frames at ${FPS}fps (${JOBS} in parallel)..."

# Render one frame. Each Chrome gets its OWN --user-data-dir: parallel
# instances sharing the default profile contend on its singleton lock, and a
# loser hangs forever instead of exiting, wedging the whole run.
# Chrome 151's headless mode writes the screenshot and then does not exit, so
# running it in the foreground blocks forever and starves the parallel slots.
# Run it in the background and act as its watchdog: wait for the PNG to appear
# and stop growing, then kill it. Waiting for a stable size matters, killing
# mid-write leaves a truncated frame that ffmpeg would happily encode.
render_frame() {
  local idx="$1" t="$2"
  local out="$FRAMES/f$idx.png"

  "$CHROME" --headless --disable-gpu --hide-scrollbars \
    --no-first-run --no-default-browser-check --no-sandbox \
    --user-data-dir="$FRAMES/ud-$idx" \
    --window-size="$WIDTH,$HEIGHT" \
    --virtual-time-budget=6000 \
    --screenshot="$out" \
    "file://$SRC?t=$t" >/dev/null 2>&1 &
  local pid=$!

  local waited=0 last=0 size=0
  while [ "$waited" -lt 400 ]; do          # 40s ceiling per frame
    if [ -s "$out" ]; then
      size=$(wc -c < "$out" 2>/dev/null || echo 0)
      [ "$size" -gt 0 ] && [ "$size" -eq "$last" ] && break
      last="$size"
    fi
    sleep 0.1
    waited=$((waited + 1))
  done

  kill -9 "$pid" 2>/dev/null || true
  wait "$pid" 2>/dev/null || true
  rm -rf "$FRAMES/ud-$idx"
}
export -f render_frame
export CHROME FRAMES SRC WIDTH HEIGHT

frame_list() {
  python3 -c "
for i in range($TOTAL):
    print(f'{i:04d} {i / $FPS:.4f}')
"
}

frame_list | xargs -P "$JOBS" -n 2 bash -c 'render_frame "$0" "$1"'

# Retry pass: a frame can still be lost to a transient Chrome failure, and one
# missing frame silently shortens the video rather than failing loudly.
for attempt in 1 2; do
  MISSING=$(frame_list | while read -r idx t; do
    [ -f "$FRAMES/f$idx.png" ] || echo "$idx $t"
  done)
  [ -z "$MISSING" ] && break
  echo "Retry $attempt for $(echo "$MISSING" | wc -l | tr -d ' ') missing frame(s)..."
  echo "$MISSING" | xargs -P "$JOBS" -n 2 bash -c 'render_frame "$0" "$1"'
done

RENDERED=$(ls "$FRAMES"/f*.png 2>/dev/null | wc -l | tr -d ' ')
echo "Rendered $RENDERED/$TOTAL frames"
if [ "$RENDERED" -ne "$TOTAL" ]; then
  echo "Frame count mismatch, aborting rather than shipping a stuttering video." >&2
  exit 1
fi

# yuv420p + even dimensions keep it playable on iOS/Instagram.
ffmpeg -y -loglevel error \
  -framerate "$FPS" -i "$FRAMES/f%04d.png" \
  -c:v libx264 -preset slow -crf 18 -pix_fmt yuv420p \
  -movflags +faststart \
  "$OUT"

echo "Wrote $OUT"
