# CEF macOS Shell — Experiment

An experiment in building a browser shell on Chromium Embedded Framework (CEF).
The window is chromeless: an Arc-style left sidebar (nav buttons, URL field,
tab list) sits next to the CEF web view, with the traffic lights floating
over the sidebar.

## Layout

- `src/main.mm` — entry point + native chrome. Loads the CEF framework,
  creates the chromeless NSWindow, builds the sidebar (`ExperimentSidebar`),
  owns the menus and quit path, runs the message loop.
- `src/sidebar.h` — bridge between CEF callbacks and the sidebar
  (`SidebarSetAddressText`, `SidebarSetTabTitle`, ...), plus `kSidebarWidth`.
- `src/theme.h` — design tokens (palette, corner radii, spacing, fonts).
  All chrome styling reads from here; see "Styling" below.
- `src/sidebar.mm` — the native sidebar: nav buttons, URL field, dynamic
  tab list (favicon + title + close), New Tab row. Implements the bridge
  functions declared in `sidebar.h`.
- `src/experiment_app.{h,mm}` — `CefApp` / `CefClient` implementations plus
  the tab registry (static tab API: `CreateTab` / `CloseTabById` /
  `ActivateTab` / `GetActiveBrowser`). No browser exists at startup; tabs
  are created on demand.
- `src/helper_main.cc` — entry point shared by the four helper app bundles
  (base, GPU, Renderer, Plugin) required by CEF's multi-process model.
- `scripts/fetch_cef.sh` — downloads + extracts a minimal CEF binary build
  into `third_party/cef`. Version is pinned via `CEF_VERSION` env var; find
  current strings at https://cef-builds.spotifycdn.com/index.html (macOS
  ARM64 Minimal).
- `CMakeLists.txt` — builds `libcef_dll_wrapper` from source, the helpers,
  and the main `Experiment.app`; assembles the bundle
  (`Contents/Frameworks/` gets the CEF framework + helper apps, each with a
  `Contents/Frameworks` symlink back to the main Frameworks dir so dyld can
  resolve `@executable_path/../Frameworks/...`), then ad-hoc codesigns.

## Build & run

```sh
# one-time: download CEF (pinned version)
CEF_VERSION="131.4.1+g437feba+chromium-131.0.6778.265" ./scripts/fetch_cef.sh

scripts/dev.sh            # build, kill old instance, relaunch
scripts/dev.sh --shot     # ...and screenshot the window to build/shot.png
scripts/dev.sh --build-only
```

Starts with an empty window (no tabs); `EXPERIMENT_START_URL` opens tabs at
launch for testing — comma-separate for several:
`EXPERIMENT_START_URL=https://github.com,https://news.ycombinator.com scripts/dev.sh`

## Screenshotting the app

`scripts/screenshot.sh [out.png]` captures just the Experiment window to
`build/shot.png`. One-time setup: grant **Screen Recording** permission to
the host app (Zed/Terminal) in System Settings → Privacy & Security → Screen
Recording; if the prompt was previously denied it won't re-appear, toggle it
manually. The script re-resolves the window ID each run (IDs change per
launch) and raises the window first, because occluded-window captures render
the GPU-backed web content as black.

## Styling

The chrome is hand-written AppKit (frames + autoresizing masks, no Auto
Layout). Shared appearance lives in `src/theme.h` as design tokens —
`theme::RowBackgroundActive()`, `theme::CornerRadiusRow()`, `theme::SpacingM()`,
etc. Components never hardcode colors/radii; they read tokens, so a restyle
is a one-file edit. Per-component layout metrics (nav button size, row
heights, insets) are constants at the top of `main.mm`.

## Gotchas discovered (worth remembering)

- CMake target names can't contain spaces → helpers use logical names
  (`helper_base`, `helper_gpu`, ...) with `OUTPUT_NAME` set to the real
  `Experiment Helper*` names.
- `framework_path` was removed from `CefSettings` in recent CEF; the
  `CefScopedLibraryLoader` handles framework loading.
- The wrapper library includes Objective-C++ sources (`*.mm`) — globbing
  only `*.cc` links but fails at runtime symbol resolution
  (`CefScopedLibraryLoader`).
- The CEF framework's install name is `@executable_path/../Frameworks/...`,
  which breaks helpers unless each helper bundle gets a
  `Contents/Frameworks -> ../..` symlink.
- The app cannot run under this repo's terminal sandbox (process spawning /
  WindowServer access gets SIGABRT with no output) — run it normally.
- Browser close is a multi-stage dance (see the `DoClose` docs in
  `cef_life_span_handler.h`): the browser's teardown is only triggered by
  DESTRUCTION of its native view, and an `NSWindow` close merely hides the
  window. `windowShouldClose:` therefore calls `TryCloseBrowser()`, returns
  its result as the allow/deny answer, and — when proceeding — explicitly
  removes the browser view from its superview to complete the teardown.
  Without that, `OnBeforeClose` never fires and the app can't quit.
- Launching a second instance while one is running prints "Opening in
  existing browser session" and exits — quit events then appear to do
  nothing. `pkill -f Experiment.app` before testing quit behavior.
- Menu shortcuts with ⇧ in the modifier mask need the keyEquivalent in
  UPPERCASE (`@"S"`, not `@"s"`) — lowercase + shift mask never matches and
  fails silently.
- Window dragging with a hidden titlebar: the titlebar area still drags, but
  chrome views need `performWindowDragWithEvent:` in `mouseDown:` for
  Arc-style "drag the sidebar background" behavior (see
  `SidebarBackgroundView`).

## Roadmap

1. ~~CEF renders a page fullscreen in a bare NSWindow~~ ✔
2. ~~OS-level menus (Edit for copy/paste, View for reload/devtools), clean
   quit path, window resizing, popup policy, cache path, mock keychain~~ ✔
3. ~~Native chrome, step 1: toolbar (back/forward/reload + URL field) wired
   to CEF navigation and load/address/title callbacks~~ ✔
4. ~~Native chrome, step 2: Arc-style left sidebar (nav + URL field + tab
   row with title/favicon), chromeless window, draggable sidebar, min
   window size~~ ✔
5. ~~Multiple tabs (browser registry keyed by `CefBrowser::GetIdentifier`,
   per-tab title/favicon, click-to-switch, ✕ close, ⌘T/⌘W, popups open as
   tabs) + empty-window start (no browser until first tab)~~ ✔
6. Polish / styling (hover states, pinned tabs, quit-confirmation dialog à
   la Arc — standard NSAlert first, custom floating card later, "don't ask
   again" via NSUserDefaults; scrollable tab list when it overflows)
7. (Later) consider a Rust port for safety, once the CEF lifecycle and macOS
   bundle requirements are fully understood here.

## Tech-debt watchlist (revisit as the experiment grows)

- Tab rows are individual views relaid out on every add/remove; with many
  tabs this wants an NSStackView or NSCollectionView, plus scrolling.
- `g_sidebar` global + free bridge functions — acceptable at this size, but
  the seam is `sidebar.h`; a BrowserController object is the natural
  successor if menu/sidebar action logic keeps growing.
- JS `beforeunload` handlers are bypassed on quit/close (CloseBrowser, not
  TryCloseBrowser) — deliberate for predictable teardown; revisit for
  correctness.
- Favicons are fetched over the network on every new `OnFaviconURLChange`
  with no disk cache; key by origin + cache.
- CEF 131 removed `OnLoadingProgressChange` from `CefLoadHandler` — a real
  progress bar isn't available from the load handler anymore.
- BENCHED BUG: ⌘⇧S (Toggle Sidebar) doesn't fire even with uppercase "S".
  Suspect CEF's content view consuming the key equivalent in the responder
  chain before the menu sees it. Needs real debugging (e.g. logging in
  `sendEvent:` / `performKeyEquivalent:`).
- With the sidebar hidden (View → Toggle Sidebar, ⌘⇧S) the traffic lights
  float over web content; Arc shows a floating control cluster there.
- `settings.no_sandbox = true` — fine locally, must change before any
  distribution.
- Ad-hoc codesigning + `use-mock-keychain` are dev-only conveniences.
- `experiment_app.mm` mixes CefApp, client, and (now) ObjC view juggling;
  split client handlers from app bootstrap when it outgrows one file.
