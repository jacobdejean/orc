#!/bin/sh
# Screenshot the Experiment window.
#
# Usage: scripts/screenshot.sh [output.png]   (default: build/shot.png)
#
# Requires macOS Screen Recording permission for the host terminal/editor
# (System Settings → Privacy & Security → Screen Recording). If you see
# "could not create image from window", that permission is missing or the
# window ID is stale — this script re-resolves the ID every run.
#
# Caveats:
# - Finds the first on-screen window owned by a process named *Experiment*.
# - Raises the window first: occluded-window captures can render the
#   GPU-backed web content as black.
# - Window IDs change every launch, so the ID is never cached.

set -e

OUT="${1:-build/shot.png}"

WID=$(swift -e '
import CoreGraphics
let wl = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as! [[String: Any]]
for w in wl {
  if let o = w["kCGWindowOwnerName"] as? String, o.contains("Experiment"),
     let wid = w["kCGWindowNumber"] as? Int {
    print(wid)
  }
}' | head -n1)

if [ -z "$WID" ]; then
  echo "error: no on-screen Experiment window found (is the app running?)" >&2
  exit 1
fi

osascript -e 'tell application "Experiment" to activate' 2>/dev/null || true
sleep 0.5
screencapture -o -l"$WID" "$OUT"
echo "captured window $WID -> $OUT"
