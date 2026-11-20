#!/usr/bin/env bash

# Run from any directory. This checks the local build environment without
# downloading anything or changing the system configuration.

set -uo pipefail

_script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
_repo_dir="$_script_dir/ungoogled-chromium-macos"
_expected_venv="$HOME/.venvs/ungoogled-chromium-build"
_failures=0

ok() {
  printf 'OK   %s\n' "$1"
}

fail() {
  printf 'FAIL %s\n' "$1" >&2
  _failures=$((_failures + 1))
}

info() {
  printf 'INFO %s\n' "$1"
}

require_command() {
  local command_name="$1"
  local install_hint="$2"
  local command_path

  if command_path="$(command -v "$command_name" 2>/dev/null)"; then
    ok "$command_name found at $command_path"
  else
    fail "$command_name not found. $install_hint"
  fi
}

printf 'Checking ungoogled-chromium-macos build environment...\n\n'

# Repository and submodule
if [[ -f "$_repo_dir/build.sh" ]]; then
  ok "macOS packaging repository found at $_repo_dir"
else
  fail "macOS packaging repository not found at $_repo_dir"
fi

if [[ -f "$_repo_dir/ungoogled-chromium/utils/downloads.py" ]]; then
  ok "ungoogled-chromium submodule is initialized"
else
  fail "ungoogled-chromium submodule is empty or uninitialized. Run: git -C '$_repo_dir' submodule update --init --recursive"
fi

# Xcode and Metal
if command -v xcode-select >/dev/null 2>&1; then
  _developer_dir="$(xcode-select -p 2>/dev/null)"
  if [[ "$_developer_dir" == *.app/Contents/Developer ]]; then
    ok "Full Xcode developer directory is active: $_developer_dir"
  else
    fail "Command Line Tools are active instead of full Xcode. Run: sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer"
  fi
else
  fail "xcode-select not found; install full Xcode"
fi

if xcodebuild -version >/dev/null 2>&1; then
  _xcode_version="$(xcodebuild -version 2>/dev/null | awk 'NR == 1 { print; exit }')"
  ok "xcodebuild works: $_xcode_version"
else
  fail "xcodebuild is unavailable. Open Xcode, accept its license, and run: xcodebuild -runFirstLaunch"
fi

if xcodebuild -showComponent MetalToolchain >/dev/null 2>&1; then
  ok "Metal toolchain is installed"
else
  fail "Metal toolchain not found. Run: xcodebuild -downloadComponent MetalToolchain"
fi

# Python environment
if [[ "${VIRTUAL_ENV:-}" == "$_expected_venv" ]]; then
  ok "Expected Python virtual environment is active"
elif [[ -n "${VIRTUAL_ENV:-}" ]]; then
  fail "A different virtual environment is active: $VIRTUAL_ENV. Run: source '$_expected_venv/bin/activate'"
else
  fail "Build virtual environment is not active. Run: source '$_expected_venv/bin/activate'"
fi

if command -v python3 >/dev/null 2>&1; then
  _python_path="$(command -v python3)"
  _python_version="$(python3 -c 'import platform; print(platform.python_version())' 2>/dev/null)"
  if python3 -c 'import sys; raise SystemExit(0 if sys.version_info[:2] == (3, 13) else 1)' >/dev/null 2>&1; then
    ok "Python $_python_version is active at $_python_path"
  else
    fail "Expected Python 3.13, found ${_python_version:-unknown} at $_python_path. Activate the build virtual environment"
  fi

  if python3 -c 'import socks, httplib2' >/dev/null 2>&1; then
    ok "Python packages PySocks and httplib2 are importable"
  else
    fail "Python packages are missing. With the build environment active, run: python -m pip install PySocks httplib2"
  fi
else
  fail "python3 not found. Create the environment with: /opt/homebrew/bin/python3.13 -m venv '$_expected_venv'"
fi

# Other required tools
require_command perl "Install Perl; macOS normally provides /usr/bin/perl"
require_command ninja "Run: brew install ninja"
require_command greadlink "Run: brew install coreutils"
require_command node "Run: brew install node"
require_command esbuild "Run: brew install esbuild"
require_command tsc "Run: brew install typescript"

if command -v brew >/dev/null 2>&1 && brew --prefix readline >/dev/null 2>&1; then
  ok "Homebrew readline is installed"
else
  fail "Homebrew readline not found. Run: brew install readline"
fi

# Signing is optional for local development. Never print credential values.
if [[ "${MACOS_AD_HOC_SIGNING:-0}" == "1" ]]; then
  ok "Ad-hoc signing selected; Apple Developer credentials are not required"
elif [[ -n "${MACOS_CERTIFICATE_NAME:-}" \
  && -n "${PROD_MACOS_NOTARIZATION_APPLE_ID:-}" \
  && -n "${PROD_MACOS_NOTARIZATION_TEAM_ID:-}" \
  && -n "${PROD_MACOS_NOTARIZATION_PWD:-}" ]]; then
  ok "Developer ID signing environment variables are set"
else
  info "Signing is not configured. For a local build, use: MACOS_AD_HOC_SIGNING=1 ./build.sh"
fi

printf '\n'
if (( _failures == 0 )); then
  printf 'OK - build environment checks passed.\n'
  exit 0
fi

printf '%d environment check(s) failed. Fix the items above and rerun this script.\n' "$_failures" >&2
exit 1
