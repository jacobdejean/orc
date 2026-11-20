#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_dir="$script_dir/ungoogled-chromium-macos"
out_dir="$repo_dir/build/src/out/Default"
binary="$out_dir/Orc.app/Contents/MacOS/Orc"
url="https://example.com"
launch=1
url_set=0
chromeless_args=()

while (( $# )); do
  case "$1" in
    --no-launch)
      launch=0
      ;;
    --chromeless)
      chromeless_args=(--orc-chromeless)
      ;;
    -h|--help)
      printf 'Usage: %s [--no-launch] [--chromeless] [URL]\n' "$0"
      exit 0
      ;;
    -*)
      printf 'Unknown option: %s\n' "$1" >&2
      exit 2
      ;;
    *)
      if (( url_set )); then
        printf 'Only one URL may be specified.\n' >&2
        exit 2
      fi
      url="$1"
      url_set=1
      ;;
  esac
  shift
done

if [[ ! -f "$out_dir/build.ninja" ]]; then
  printf 'No configured build found at %s. Run the initial full build first; dev.sh never runs build.sh.\n' "$out_dir" >&2
  exit 1
fi

orc_source_dir="$repo_dir/orc"
orc_build_dir="$repo_dir/build/src/orc"
if [[ -L "$orc_build_dir" ]]; then
  if [[ "$(greadlink -f "$orc_build_dir")" != "$orc_source_dir" ]]; then
    printf 'Refusing to replace Orc source symlink with another target: %s\n' "$orc_build_dir" >&2
    exit 1
  fi
elif [[ -e "$orc_build_dir" ]]; then
  printf 'Refusing to replace existing non-symlink source path: %s\n' "$orc_build_dir" >&2
  exit 1
else
  ln -s "$orc_source_dir" "$orc_build_dir"
fi

venv="$HOME/.venvs/ungoogled-chromium-build"
if [[ -f "$venv/bin/activate" ]]; then
  source "$venv/bin/activate"
fi

sdk="/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk"
if [[ -d "$sdk" ]]; then
  export SDKROOT="$sdk"
fi

SECONDS=0
ninja -C "$out_dir" chrome
MACOS_AD_HOC_SIGNING=1 MACOS_SIGN_ONLY=1 "$repo_dir/sign_and_package_app.sh"
printf 'Incremental build and signing completed in %ss.\n' "$SECONDS"

if (( ! launch )); then
  exit 0
fi

# Stop only a previous Orc dev instance launched from this exact binary path.
pattern="^${binary}([[:space:]]|$)"
pkill -TERM -f "$pattern" 2>/dev/null || true
for _ in {1..50}; do
  if ! pgrep -f "$pattern" >/dev/null 2>&1; then
    break
  fi
  sleep 0.1
done
if pgrep -f "$pattern" >/dev/null 2>&1; then
  pkill -KILL -f "$pattern" 2>/dev/null || true
fi

"$binary" \
  --user-data-dir=/tmp/orc-dev-profile \
  --no-first-run \
  --no-default-browser-check \
  --new-window \
  "${chromeless_args[@]}" \
  "$url" >/dev/null 2>&1 &
printf 'Launched %s with %s\n' "$binary" "$url"
