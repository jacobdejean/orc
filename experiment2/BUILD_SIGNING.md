# Build Signing Plan

## Overview

Upstream's Apple Developer Program announcement affects only the prebuilt binaries distributed by `ungoogled-chromium-macos`. It does not prevent this fork from being built, signed, and notarized with our own Apple Developer account.

The existing packaging script, `ungoogled-chromium-macos/sign_and_package_app.sh`, accepts a custom signing identity and notarization credentials. No upstream certificate is hardcoded.

## Development Builds: Ad-Hoc Signing

Use ad-hoc signing for the initial unmodified build and early chromeless experiments. This avoids making Apple credentials and notarization part of the inner development loop.

From `experiment2/ungoogled-chromium-macos/`:

```sh
MACOS_AD_HOC_SIGNING=1 ./build.sh
```

This signs the application for local use, skips notarization and ticket stapling, and still produces a DMG. It does not require a paid Apple Developer Program membership.

If compilation succeeds but packaging needs to be rerun:

```sh
MACOS_AD_HOC_SIGNING=1 ./sign_and_package_app.sh
```

## Distribution Builds: Developer ID

### Prerequisites

- An active Apple Developer Program membership.
- A **Developer ID Application** certificate and its private key installed in an accessible keychain on the build machine. An Apple Development certificate is not sufficient.
- The Apple Account email associated with the developer account.
- The Apple Developer Team ID.
- An app-specific password for notarization, not the normal Apple Account password.

List available code-signing identities:

```sh
security find-identity -v -p codesigning
```

Use the full identity beginning with `Developer ID Application:`. If multiple identities have the same name, the certificate's SHA-1 fingerprint can be used instead.

### Credentials

Set these in the build shell, not in a tracked file:

```sh
export MACOS_CERTIFICATE_NAME='Developer ID Application: Your Name (TEAMID)'
export PROD_MACOS_NOTARIZATION_APPLE_ID='your-apple-account@example.com'
export PROD_MACOS_NOTARIZATION_TEAM_ID='YOUR_TEAM_ID'
export PROD_MACOS_NOTARIZATION_PWD='your-app-specific-password'
```

`PROD_MACOS_NOTARIZATION_PWD` is a secret. Do not commit it, include it in build logs, or save it in this repository.

### Build and Package

From `experiment2/ungoogled-chromium-macos/`:

```sh
./build.sh
```

To rerun packaging after a successful compilation:

```sh
./sign_and_package_app.sh
```

For Developer ID builds, the packaging script:

1. Signs Chromium, its framework, helper applications, and dylibs.
2. Uses the hardened runtime and secure signing timestamps.
3. Verifies the signatures and signing identifiers.
4. Submits the application to Apple with `notarytool`.
5. Requires an `Accepted` notarization result.
6. Staples and validates the notarization ticket.
7. Creates the DMG.

## Recommended Order

1. Build the unmodified upstream tag with ad-hoc signing.
2. Establish the chromeless launcher and minimal downstream patches.
3. Continue using ad-hoc signing for local iteration.
4. Validate a Developer ID signed and notarized build once the chromeless application works.
5. Revisit credential storage and signing automation before CI or external distribution; do not automate secrets into tracked configuration.

## Scope

Signing and notarization are independent of the chromeless and ADK implementation. Upstream's signing support ending is therefore not a blocker for this experiment.
