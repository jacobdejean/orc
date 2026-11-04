#!/bin/sh
# Build → kill any running instance → relaunch → optionally screenshot.
#
# Usage:
#   scripts/dev.sh            build + relaunch
#   scripts/dev.sh --shot     build + relaunch + capture window to build/shot.png
#   scripts/dev.sh --build-only
#
# Env:
#   EXPERIMENT_START_URL   first page to load (default https://example.com)
#   EXPERIMENT_LOG         log file (default build/exp.log)
#
# Killing first is required: launching while an old instance lives prints
# "Opening in existing browser session" and exits, which looks like the new
# build silently failed.

set -e
cd "$(dirname "$0")/.."

LOG="${EXPERIMENT_LOG:-build/exp.log}"

cmake -B build -DCMAKE_BUILD_TYPE=Release
cmake --build build -j 2>&1 | grep -vE "xcrun_db|replacing existing"

if [ "$1" = "--build-only" ]; then
  exit 0
fi

pkill -9 -f "Experiment.app" 2>/dev/null || true
sleep 0.5

build/Experiment.app/Contents/MacOS/Experiment > "$LOG" 2>&1 &
echo "launched (pid $!), log: $LOG"
sleep 5

if [ "$1" = "--shot" ]; then
  scripts/screenshot.sh build/shot.png
fi
