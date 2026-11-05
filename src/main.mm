#import <Cocoa/Cocoa.h>

#include "include/cef_app.h"
#include "include/cef_application_mac.h"
#include "include/wrapper/cef_helpers.h"
#include "include/wrapper/cef_library_loader.h"

#include "experiment_app.h"
#include "sidebar.h"
#include "theme.h"

// Set by main.mm before CefInitialize; consumed by ExperimentClient when
// creating tabs.
void SetParentViewForBrowser(void* view);

// CEF requires the NSApplication object to conform to CefAppProtocol so it
// can wrap event dispatch (context menus spin nested run loops inside
// sendEvent: and crash without this).
@interface ExperimentApplication : NSApplication <CefAppProtocol> {
  BOOL handlingSendEvent_;
}
@end

@implementation ExperimentApplication
- (BOOL)isHandlingSendEvent {
  return handlingSendEvent_;
}
- (void)setHandlingSendEvent:(BOOL)handlingSendEvent {
  handlingSendEvent_ = handlingSendEvent;
}
- (void)sendEvent:(NSEvent*)event {
  CefScopedSendingEvent sendingEvent;
  [super sendEvent:event];
}
@end

// App surface: the vibrant-material backdrop the web view card sits on.
// Always visible; only the empty-state card (rounded placeholder with the
// "no tabs" hint) toggles via StartViewSetVisible.
static NSView* g_start_view = nil;
static NSView* g_start_card = nil;
static NSTextField* g_start_label = nil;

void StartViewSetVisible(bool visible) {
  [g_start_card setHidden:!visible];
}

// Handles app lifecycle (clean quit) and menu actions that talk to CEF.
@interface ExperimentAppDelegate : NSObject <NSApplicationDelegate,
                                             NSWindowDelegate>
@end

@implementation ExperimentAppDelegate

// Cmd+Q / menu Quit: close all browsers first; the last OnBeforeClose runs
// CefQuitMessageLoop, after which main() calls CefShutdown and exits.
- (NSApplicationTerminateReply)applicationShouldTerminate:
    (NSApplication*)sender {
  ExperimentClient::SetTerminating();
  if (ExperimentClient::HasTabs()) {
    ExperimentClient::CloseAllBrowsers();
    return NSTerminateCancel;
  }
  return NSTerminateNow;
}

// Red close button: with a single window, closing it means quitting. Close
// all browsers; the last one's OnBeforeClose quits the message loop. We
// return NO (don't close the window yet) because browser teardown is
// asynchronous — the process exits once all browsers are gone.
- (BOOL)windowShouldClose:(NSWindow*)sender {
  ExperimentClient::SetTerminating();
  if (ExperimentClient::HasTabs()) {
    ExperimentClient::CloseAllBrowsers();
  } else {
    CefQuitMessageLoop();
  }
  return NO;
}

// NOTE: JS beforeunload handlers are not honored on quit/close (CloseBrowser
// bypasses them; TryCloseBrowser would defer). Revisit if we ever need it —
// the experiment optimizes for predictable teardown.

- (IBAction)newTab:(id)sender {
  ExperimentClient::CreateTab("about:blank");
}

- (IBAction)closeTab:(id)sender {
  if (CefRefPtr<CefBrowser> browser = ExperimentClient::GetActiveBrowser()) {
    ExperimentClient::CloseTabById(browser->GetIdentifier());
  } else {
    [NSApp terminate:nil];
  }
}

- (IBAction)reload:(id)sender {
  if (CefRefPtr<CefBrowser> browser = ExperimentClient::GetActiveBrowser()) {
    browser->Reload();
  }
}

- (IBAction)toggleDevTools:(id)sender {
  if (CefRefPtr<CefBrowser> browser = ExperimentClient::GetActiveBrowser()) {
    browser->GetHost()->ShowDevTools(CefWindowInfo(), new ExperimentClient(),
                                     CefBrowserSettings(), CefPoint());
  }
}

- (IBAction)toggleSidebar:(id)sender {
  SidebarToggleHidden();
}

@end

namespace {

NSMenu* CreateAppMenu(ExperimentAppDelegate* delegate) {
  NSMenu* menubar = [[NSMenu alloc] init];

  // Application menu.
  NSMenuItem* appMenuItem = [[NSMenuItem alloc] init];
  [menubar addItem:appMenuItem];
  NSMenu* appMenu = [[NSMenu alloc] init];
  [appMenu addItemWithTitle:@"Quit Experiment"
                     action:@selector(terminate:)
              keyEquivalent:@"q"];
  [appMenuItem setSubmenu:appMenu];

  // File menu.
  NSMenuItem* fileMenuItem = [[NSMenuItem alloc] init];
  [menubar addItem:fileMenuItem];
  NSMenu* fileMenu = [[NSMenu alloc] initWithTitle:@"File"];
  [fileMenu addItemWithTitle:@"New Tab"
                      action:@selector(newTab:)
               keyEquivalent:@"t"];
  [fileMenu addItemWithTitle:@"Close Tab"
                      action:@selector(closeTab:)
               keyEquivalent:@"w"];
  [fileMenuItem setSubmenu:fileMenu];

  // Edit menu: required for copy/paste/select-all in web content, which the
  // Chromium NSView implements via standard responder selectors.
  NSMenuItem* editMenuItem = [[NSMenuItem alloc] init];
  [menubar addItem:editMenuItem];
  NSMenu* editMenu = [[NSMenu alloc] initWithTitle:@"Edit"];
  [editMenu addItemWithTitle:@"Undo" action:@selector(undo:) keyEquivalent:@"z"];
  [editMenu addItemWithTitle:@"Redo" action:@selector(redo:) keyEquivalent:@"Z"];
  [editMenu addItem:[NSMenuItem separatorItem]];
  [editMenu addItemWithTitle:@"Cut" action:@selector(cut:) keyEquivalent:@"x"];
  [editMenu addItemWithTitle:@"Copy" action:@selector(copy:) keyEquivalent:@"c"];
  [editMenu addItemWithTitle:@"Paste" action:@selector(paste:) keyEquivalent:@"v"];
  [editMenu addItemWithTitle:@"Select All" action:@selector(selectAll:) keyEquivalent:@"a"];
  [editMenuItem setSubmenu:editMenu];

  // View menu.
  NSMenuItem* viewMenuItem = [[NSMenuItem alloc] init];
  [menubar addItem:viewMenuItem];
  NSMenu* viewMenu = [[NSMenu alloc] initWithTitle:@"View"];
  [viewMenu addItemWithTitle:@"Reload"
                      action:@selector(reload:)
               keyEquivalent:@"r"];
  NSMenuItem* sidebarItem =
      [viewMenu addItemWithTitle:@"Toggle Sidebar"
                          action:@selector(toggleSidebar:)
                   keyEquivalent:@"S"];  // uppercase when mask has shift
  [sidebarItem setKeyEquivalentModifierMask:NSEventModifierFlagCommand |
                                            NSEventModifierFlagShift];
  NSMenuItem* devToolsItem =
      [viewMenu addItemWithTitle:@"Toggle Developer Tools"
                          action:@selector(toggleDevTools:)
                   keyEquivalent:@"i"];
  [devToolsItem setKeyEquivalentModifierMask:NSEventModifierFlagCommand |
                                             NSEventModifierFlagOption];
  [viewMenuItem setSubmenu:viewMenu];

  // Window menu.
  NSMenuItem* windowMenuItem = [[NSMenuItem alloc] init];
  [menubar addItem:windowMenuItem];
  NSMenu* windowMenu = [[NSMenu alloc] initWithTitle:@"Window"];
  [windowMenu addItemWithTitle:@"Minimize"
                        action:@selector(performMiniaturize:)
                 keyEquivalent:@"m"];
  [windowMenu addItemWithTitle:@"Zoom"
                        action:@selector(performZoom:)
                 keyEquivalent:@""];
  [windowMenu addItem:[NSMenuItem separatorItem]];
  NSMenuItem* closeWindowItem =
      [windowMenu addItemWithTitle:@"Close Window"
                            action:@selector(performClose:)
                     keyEquivalent:@"W"];  // ⇧⌘W; ⌘W is Close Tab
  [closeWindowItem setKeyEquivalentModifierMask:NSEventModifierFlagCommand |
                                                NSEventModifierFlagShift];
  [windowMenuItem setSubmenu:windowMenu];
  [NSApp setWindowsMenu:windowMenu];

  return menubar;
}

// App surface + empty-state card. The surface is the vibrant-material
// backdrop the web view card sits on (always visible). On top of it sits
// the empty-state card: a lighter, rounded vibrant view inset exactly like
// the web view card, so the empty window previews where content will
// appear. StartViewSetVisible toggles the card (and its hint label).
NSView* CreateStartView(NSRect bounds) {
  NSVisualEffectView* view = [[NSVisualEffectView alloc] initWithFrame:bounds];
  [view setMaterial:NSVisualEffectMaterialSidebar];
  [view setBlendingMode:NSVisualEffectBlendingModeBehindWindow];
  [view setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];

  // The card mirrors LayoutBrowserView's geometry (minus the sidebar-left
  // offset, which is constant here).
  const CGFloat pad = kWebViewPadding;
  NSRect cardFrame = NSMakeRect(kSidebarWidth + pad, pad,
                                bounds.size.width - kSidebarWidth - 2 * pad,
                                bounds.size.height - 2 * pad);
  NSVisualEffectView* card =
      [[NSVisualEffectView alloc] initWithFrame:cardFrame];
  [card setMaterial:NSVisualEffectMaterialPopover];
  [card setBlendingMode:NSVisualEffectBlendingModeBehindWindow];
  [card setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
  [card setWantsLayer:YES];
  [[card layer] setCornerRadius:kWebViewCornerRadius];
  [[card layer] setMasksToBounds:YES];
  [view addSubview:card];

  // The blur materials alone barely differ from the surface on busy
  // wallpapers, so lift the card with a subtle white overlay.
  NSView* lift = [[NSView alloc] initWithFrame:[card bounds]];
  [lift setWantsLayer:YES];
  [[lift layer]
      setBackgroundColor:[[NSColor colorWithWhite:1.0 alpha:0.08] CGColor]];
  [lift setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
  [card addSubview:lift];

  g_start_label = [[NSTextField alloc]
      initWithFrame:NSMakeRect(0, cardFrame.size.height / 2 - 12,
                               cardFrame.size.width, 24)];
  [g_start_label setEditable:NO];
  [g_start_label setBezeled:NO];
  [g_start_label setDrawsBackground:NO];
  [g_start_label setAlignment:NSTextAlignmentCenter];
  [g_start_label setFont:[NSFont systemFontOfSize:13
                                         weight:NSFontWeightMedium]];
  [g_start_label setTextColor:[NSColor tertiaryLabelColor]];
  [g_start_label setStringValue:@"⌘T for a new tab"];
  [g_start_label setAutoresizingMask:NSViewWidthSizable | NSViewMinYMargin |
                                     NSViewMaxYMargin];
  [card addSubview:g_start_label];
  g_start_card = card;
  return view;
}

}  // namespace

int main(int argc, char* argv[]) {
  // Load the CEF framework library at runtime (it lives inside the app
  // bundle; see CMakeLists.txt for the bundle layout).
  CefScopedLibraryLoader library_loader;
  if (!library_loader.LoadInMain()) {
    return 1;
  }

  CefMainArgs main_args(argc, argv);
  CefRefPtr<ExperimentApp> app(new ExperimentApp());

  @autoreleasepool {
    [ExperimentApplication sharedApplication];
    [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];

    ExperimentAppDelegate* delegate = [[ExperimentAppDelegate alloc] init];
    [NSApp setDelegate:delegate];
    [NSApp setMainMenu:CreateAppMenu(delegate)];

    NSRect frame = NSMakeRect(0, 0, 1200, 800);
    NSWindow* window = [[NSWindow alloc]
        initWithContentRect:frame
                  styleMask:(NSWindowStyleMaskTitled |
                             NSWindowStyleMaskClosable |
                             NSWindowStyleMaskMiniaturizable |
                             NSWindowStyleMaskResizable |
                             NSWindowStyleMaskFullSizeContentView)
                    backing:NSBackingStoreBuffered
                      defer:NO];
    [window setTitle:@"Experiment"];
    // Chromeless window: hide the titlebar so the traffic lights float over
    // the sidebar, Arc-style. Content extends under the titlebar area.
    [window setTitlebarAppearsTransparent:YES];
    [window setTitleVisibility:NSWindowTitleHidden];
    [window center];
    [window setDelegate:delegate];
    [window setMinSize:NSMakeSize(kSidebarWidth + 240, 225)];
    [window setReleasedWhenClosed:YES];

    NSView* contentView = [window contentView];
    SetParentViewForBrowser(contentView);

    // App surface: spans the full content area (the sidebar floats over
    // the left edge; same material, so it reads as one surface). The hint
    // label hides once the first tab opens.
    g_start_view = CreateStartView([contentView bounds]);
    [contentView addSubview:g_start_view];

    // Sidebar pinned to the left edge, full height (it also underlays the
    // traffic lights in the hidden-titlebar area).
    SidebarCreate(contentView, frame.size.height);

    CefSettings settings;
    settings.no_sandbox = true;
    settings.windowless_rendering_enabled = false;

    NSString* bundlePath = [[NSBundle mainBundle] bundlePath];
    NSString* frameworksPath =
        [bundlePath stringByAppendingPathComponent:@"Contents/Frameworks"];
    CefString(&settings.main_bundle_path) = [bundlePath UTF8String];
    CefString(&settings.browser_subprocess_path) =
        [[frameworksPath stringByAppendingPathComponent:
            @"Experiment Helper.app/Contents/MacOS/Experiment Helper"]
            UTF8String];

    // Explicit cache location (silences the resource_util warning and avoids
    // process-singleton surprises when running multiple builds).
    NSString* cachePath =
        [[NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory,
                                              NSUserDomainMask, YES)
            firstObject] stringByAppendingPathComponent:@"Experiment"];
    CefString(&settings.root_cache_path) = [cachePath UTF8String];

    if (!CefInitialize(main_args, settings, app.get(), nullptr)) {
      return 1;
    }

    // Test hook: EXPERIMENT_AUTOCLOSE_SEC=5 closes the active tab after 5s,
    // for screenshot-verifying the no-tabs state without input injection.
    if (const char* secs = getenv("EXPERIMENT_AUTOCLOSE_SEC")) {
      dispatch_after(
          dispatch_time(DISPATCH_TIME_NOW,
                        (int64_t)(atof(secs) * NSEC_PER_SEC)),
          dispatch_get_main_queue(), ^{
            if (CefRefPtr<CefBrowser> b =
                    ExperimentClient::GetActiveBrowser()) {
              ExperimentClient::CloseTabById(b->GetIdentifier());
            }
          });
    }

    [window makeKeyAndOrderFront:nil];
    [NSApp activateIgnoringOtherApps:YES];
    // Drop our ARC reference; NSApp's window list retains the window until
    // it closes, at which point releasedWhenClosed lets it deallocate.
    window = nil;

    CefRunMessageLoop();
    CefShutdown();
  }
  return 0;
}
