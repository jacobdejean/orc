# CEF macOS Shell — Experiment

An experiment in building a browser shell on Chromium Embedded Framework (CEF),
starting with the minimal happy path: CEF rendering a page inside a plain
NSWindow, with the app bundle structured so native browser chrome (tab strip,
sidebar, URL bar) can be added around the web view later.

## Layout

- `src/main.mm` — entry point. Loads the CEF framework, creates the NSWindow,
  points CEF at the helper app + bundle paths, runs the message loop.
- `src/experiment_app.{h,cc}` — `CefApp` / `CefClient` implementations.
  `OnContextInitialized` creates the browser as a child of the window's
  contentView (the seam where future chrome UI will take over layout).
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

cmake -B build -DCMAKE_BUILD_TYPE=Release
cmake --build build -j
open build/Experiment.app   # or run Contents/MacOS/Experiment directly
```

Currently loads https://example.com.

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

## Roadmap

1. ~~CEF renders a page fullscreen in a bare NSWindow~~ ✔
2. ~~OS-level menus (Edit for copy/paste, View for reload/devtools), clean
   quit path, window resizing, popup policy, cache path, mock keychain~~ ✔
3. ~~Native chrome, step 1: toolbar (back/forward/reload + URL field) wired
   to CEF navigation and load/address/title callbacks~~ ✔
4. Native chrome, step 2: sidebar / tab strip as sibling NSViews
5. Multiple tabs (multiple `CefBrowser` instances, swap visible view)
6. Polish / styling
7. (Later) consider a Rust port for safety, once the CEF lifecycle and macOS
   bundle requirements are fully understood here.

## Tech-debt watchlist (revisit as the experiment grows)

- `g_first_browser` / `GetFirstBrowserForTesting` global — replace with a
  browser registry when tabs land (milestone 5). Same for `g_toolbar`.
- `ExperimentAppDelegate` is accumulating "native UI → CEF" actions; promote
  to a BrowserController once the tab strip exists.
- `settings.no_sandbox = true` — fine locally, must change before any
  distribution.
- Ad-hoc codesigning + `use-mock-keychain` are dev-only conveniences.
- `experiment_app.mm` mixes CefApp, client, and (now) ObjC view juggling;
  split client handlers from app bootstrap when it outgrows one file.
