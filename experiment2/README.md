# Orc experiment 2

## Development build

After the initial full build has completed successfully, run:

```sh
./dev.sh
```

This incrementally builds only the `chrome` target, ad-hoc re-signs `Orc.app`, verifies its signatures, and launches it with a separate `/tmp/orc-dev-profile` profile. It opens <https://example.com> by default. To use another URL or to build and sign without launching:

```sh
./dev.sh https://www.chromium.org
./dev.sh --no-launch
./dev.sh --chromeless
```

`--chromeless` launches the same normal browser model with `--orc-chromeless`, hiding the tab strip, toolbar, location bar, and bookmark bar while retaining the standard macOS window controls. Without this option, `dev.sh` launches normal Chromium UI.

The script works from any current directory when invoked by its path. It never runs the clean `build.sh` flow, deletes `out`, regenerates the source tree, builds chromedriver, notarizes, staples, or creates a DMG. The initial full build remains a prerequisite; `dev.sh` exits with an error if `build/src/out/Default/build.ninja` is missing.

## Initial environment notes

Issues fixed in the build process:

- Configured the initial environment as stated in the upstream README.
- Switched the Xcode select path.
- Added the Go dependency.
- Used the latest working Xcode CLT SDK: `/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk`.
