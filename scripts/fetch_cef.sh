#!/bin/sh
# Downloads and extracts the minimal CEF binary distribution into third_party/cef.
#
# Usage: CEF_VERSION="<version string>" ./scripts/fetch_cef.sh
#
# Find the current version string at https://cef-builds.spotifycdn.com/index.html
# (macOS ARM64 Minimal). Example:
#   CEF_VERSION="131.4.1+g437feba+chromium-131.0.6778.265" ./scripts/fetch_cef.sh
set -eu

: "${CEF_VERSION:?Set CEF_VERSION (see header comment)}"

PLATFORM="${CEF_PLATFORM:-macosarm64}"
FILENAME="cef_binary_${CEF_VERSION}_${PLATFORM}_minimal.tar.bz2"
URL="https://cef-builds.spotifycdn.com/${FILENAME}"

mkdir -p third_party
TMP_ARCHIVE="$TMPDIR/$FILENAME"

echo "Downloading $URL"
curl -fL --retry 2 -o "$TMP_ARCHIVE" "$URL"

echo "Extracting to third_party/cef"
rm -rf "third_party/cef_binary_${CEF_VERSION}_${PLATFORM}_minimal" third_party/cef
tar -xjf "$TMP_ARCHIVE" -C third_party
mv "third_party/cef_binary_${CEF_VERSION}_${PLATFORM}_minimal" third_party/cef

echo "Done. CEF is in third_party/cef"
