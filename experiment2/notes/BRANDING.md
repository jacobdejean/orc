# Orc Branding Status

## What changed

The current downstream `BRANDING` patch renames product and installer names to **Orc**. Build output now includes:

- `Orc.app` and the `Orc` executable
- `Orc Framework.framework`
- `Orc Helper*.app`
- An Orc-named DMG volume

macOS product surfaces can now display **Orc**.

## What did not change

- The bundle ID remains `io.ungoogled-software.ungoogled-chromium`.
- Existing profile locations remain unchanged.
- Many WebUI and resource strings still say **Chromium**, including “Your Chromium,” customize/manage-profile text, About Chromium, settings descriptions, and the toolbar search chip.
- Icons and ungoogled-chromium version/provenance information remain unchanged.
- Internal source and GN identifiers such as the `chrome` target and `chrome://` remain technical identifiers, not product-naming goals.

## What can still change

User-visible Chromium labels in profile menus, the toolbar, and settings can be selectively reworded or rebranded later. Neutral wording such as **“Your Profile”** is an option where product-specific naming is unnecessary. Icons and other visual resources may also be updated selectively.

Screens that the custom UI will remove should **not** receive exhaustive rebranding. Prioritize persistent, user-visible surfaces over internal labels or temporary UI.

## What must never change

- Never remove or alter required Chromium or third-party copyright, license, or open-source attribution notices.
- Never imply that Orc is not Chromium-based.
- Preserve upstream version and provenance information, including ungoogled-chromium provenance.
- Do not treat internal technical identifiers as branding obligations.

## Strategy note

Use the supplied screenshots as a record of remaining visible labels, not as a mandate to replace every Chromium string. Rebrand durable UI selectively, avoid work on screens scheduled for removal, and retain all required notices and provenance.
