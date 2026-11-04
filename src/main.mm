#import <Cocoa/Cocoa.h>

#include "include/cef_app.h"
#include "include/cef_application_mac.h"
#include "include/wrapper/cef_helpers.h"
#include "include/wrapper/cef_library_loader.h"

#include "experiment_app.h"
#include "toolbar.h"

// Set by main.mm before CefInitialize; consumed in OnContextInitialized.
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

// Native toolbar: back/forward/reload buttons plus a URL field, pinned to
// the top of the window. Talks to CEF through GetFirstBrowserForTesting,
// same as the menu actions — both get absorbed into a real controller
// class once the UI grows.
@interface ExperimentToolbar : NSObject <NSTextFieldDelegate> {
  NSVisualEffectView* bar_;
  NSButton* backButton_;
  NSButton* forwardButton_;
  NSButton* reloadButton_;
  NSTextField* addressField_;
}
- (NSView*)view;
- (void)setAddressText:(NSString*)url;
- (void)setLoadingState:(BOOL)loading
             canGoBack:(BOOL)canGoBack
          canGoForward:(BOOL)canGoForward;
@end

@implementation ExperimentToolbar

- (instancetype)init {
  if ((self = [super init])) {
    bar_ = [[NSVisualEffectView alloc] init];
    [bar_ setMaterial:NSVisualEffectMaterialHeaderView];
    // Pinned to the top of the contentView (bottom-origin coordinates, so
    // the MinY margin stays flexible).
    [bar_ setAutoresizingMask:NSViewWidthSizable | NSViewMinYMargin];

    const CGFloat pad = 8;
    const CGFloat buttonWidth = 32;
    CGFloat x = pad;
    backButton_ = [self makeButtonWithTitle:@"◀"
                                     action:@selector(goBack:)
                                      frame:NSMakeRect(x, 4, buttonWidth, kToolbarHeight - 8)];
    x += buttonWidth + 4;
    forwardButton_ = [self makeButtonWithTitle:@"▶"
                                        action:@selector(goForward:)
                                         frame:NSMakeRect(x, 4, buttonWidth, kToolbarHeight - 8)];
    x += buttonWidth + 4;
    reloadButton_ = [self makeButtonWithTitle:@"⟳"
                                       action:@selector(reloadPage:)
                                        frame:NSMakeRect(x, 4, buttonWidth, kToolbarHeight - 8)];
    x += buttonWidth + pad;

    const CGFloat fieldX = x;
    addressField_ = [[NSTextField alloc]
        initWithFrame:NSMakeRect(fieldX, 6, 600, kToolbarHeight - 12)];
    [addressField_ setBezelStyle:NSTextFieldRoundedBezel];
    [addressField_ setPlaceholderString:@"Search or enter address"];
    [addressField_ setTarget:self];
    [addressField_ setAction:@selector(addressEntered:)];
    // Stretch with the bar, keeping the trailing margin fixed.
    [addressField_ setAutoresizingMask:NSViewWidthSizable];
    [bar_ addSubview:addressField_];
  }
  return self;
}

- (NSButton*)makeButtonWithTitle:(NSString*)title
                          action:(SEL)action
                           frame:(NSRect)frame {
  NSButton* button = [[NSButton alloc] initWithFrame:frame];
  [button setTitle:title];
  [button setBezelStyle:NSBezelStyleRegularSquare];
  [button setTarget:self];
  [button setAction:action];
  [button setAutoresizingMask:NSViewMaxXMargin];
  [bar_ addSubview:button];
  return button;
}

- (NSView*)view {
  return bar_;
}

- (void)setAddressText:(NSString*)url {
  // Don't stomp on text the user is actively editing.
  if ([addressField_ currentEditor] == nil) {
    [addressField_ setStringValue:url];
  }
}

- (void)setLoadingState:(BOOL)loading
             canGoBack:(BOOL)canGoBack
          canGoForward:(BOOL)canGoForward {
  [backButton_ setEnabled:canGoBack];
  [forwardButton_ setEnabled:canGoForward];
  [reloadButton_ setTitle:loading ? @"✕" : @"⟳"];
}

- (void)goBack:(id)sender {
  if (CefRefPtr<CefBrowser> browser =
          ExperimentClient::GetFirstBrowserForTesting()) {
    browser->GoBack();
  }
}

- (void)goForward:(id)sender {
  if (CefRefPtr<CefBrowser> browser =
          ExperimentClient::GetFirstBrowserForTesting()) {
    browser->GoForward();
  }
}

- (void)reloadPage:(id)sender {
  if (CefRefPtr<CefBrowser> browser =
          ExperimentClient::GetFirstBrowserForTesting()) {
    if (browser->IsLoading()) {
      browser->StopLoad();
    } else {
      browser->Reload();
    }
  }
}

- (void)addressEntered:(id)sender {
  std::string text = [[addressField_ stringValue] UTF8String];
  if (text.empty()) {
    return;
  }
  // Bare input gets treated as a URL with an https:// prefix. (Search
  // engine fallback comes later with an actual omnibox.)
  if (text.find("://") == std::string::npos) {
    text = "https://" + text;
  }
  if (CefRefPtr<CefBrowser> browser =
          ExperimentClient::GetFirstBrowserForTesting()) {
    browser->GetMainFrame()->LoadURL(text);
  }
}

@end

// Toolbar bridge used by the CEF client (see toolbar.h).
static ExperimentToolbar* g_toolbar = nil;

void ToolbarSetAddressText(const std::string& url) {
  [g_toolbar setAddressText:[NSString stringWithUTF8String:url.c_str()]];
}

void ToolbarSetLoadingState(bool is_loading, bool can_go_back,
                            bool can_go_forward) {
  [g_toolbar setLoadingState:is_loading
                  canGoBack:can_go_back
               canGoForward:can_go_forward];
}

// Handles app lifecycle (clean quit) and menu actions that talk to CEF.
// NOTE: this object is where "native UI → browser command" wiring should
// accumulate; once more than a handful of actions exist, promote it (and the
// g_first_browser global) into a real BrowserController class.
@interface ExperimentAppDelegate : NSObject <NSApplicationDelegate,
                                             NSWindowDelegate>
@end

@implementation ExperimentAppDelegate

// Cmd+Q / menu Quit: close browsers first; OnBeforeClose runs
// CefQuitMessageLoop, after which main() calls CefShutdown and exits.
- (NSApplicationTerminateReply)applicationShouldTerminate:
    (NSApplication*)sender {
  if (CefRefPtr<CefBrowser> browser =
          ExperimentClient::GetFirstBrowserForTesting()) {
    browser->GetHost()->CloseBrowser(false);
    return NSTerminateCancel;
  }
  return NSTerminateNow;
}

// Red close button: route through the browser close path (which quits the
// app) instead of destroying the NSWindow out from under CEF.
- (BOOL)windowShouldClose:(NSWindow*)sender {
  if (CefRefPtr<CefBrowser> browser =
          ExperimentClient::GetFirstBrowserForTesting()) {
    // TryCloseBrowser returns true if the close will proceed immediately
    // (window may close now) and false if it's delayed by JavaScript unload
    // handlers (keep the window open; CEF re-triggers the close when ready).
    if (browser->GetHost()->TryCloseBrowser()) {
      // Complete the browser close by tearing down the view hierarchy
      // ourselves. We can't rely on NSWindow destruction for this: closing
      // only hides the window, and in practice the window leaks anyway, so
      // the browser view would never be destroyed and OnBeforeClose would
      // never fire.
      NSView* browserView =
          (__bridge NSView*)browser->GetHost()->GetWindowHandle();
      [browserView removeFromSuperview];
      return YES;
    }
    return NO;
  }
  CefQuitMessageLoop();
  return NO;
}

- (IBAction)reload:(id)sender {
  if (CefRefPtr<CefBrowser> browser =
          ExperimentClient::GetFirstBrowserForTesting()) {
    browser->Reload();
  }
}

- (IBAction)toggleDevTools:(id)sender {
  if (CefRefPtr<CefBrowser> browser =
          ExperimentClient::GetFirstBrowserForTesting()) {
    browser->GetHost()->ShowDevTools(CefWindowInfo(), new ExperimentClient(),
                                     CefBrowserSettings(), CefPoint());
  }
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
  [windowMenu addItemWithTitle:@"Close Window"
                        action:@selector(performClose:)
                 keyEquivalent:@"w"];
  [windowMenuItem setSubmenu:windowMenu];
  [NSApp setWindowsMenu:windowMenu];

  return menubar;
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
                             NSWindowStyleMaskResizable)
                    backing:NSBackingStoreBuffered
                      defer:NO];
    [window setTitle:@"Experiment"];
    [window center];
    [window setDelegate:delegate];
    // The browser's teardown (step 9 of the DoClose contract) is triggered
    // by DESTRUCTION of the top-level window's view hierarchy, not merely
    // by closing it. Default NSWindow close behavior only hides the window,
    // which would leave the browser half-closed and OnBeforeClose would
    // never fire. So: release-on-close, and don't hold our own strong ref.
    [window setReleasedWhenClosed:YES];

    // The web content renders into this view. Native chrome (tab strip,
    // sidebar) will later be added as sibling subviews of the contentView.
    NSView* contentView = [window contentView];
    SetParentViewForBrowser(contentView);

    // Toolbar strip across the top; the browser view is laid out below it
    // in OnAfterCreated.
    g_toolbar = [[ExperimentToolbar alloc] init];
    NSView* toolbarView = [g_toolbar view];
    [toolbarView setFrame:NSMakeRect(0, frame.size.height - kToolbarHeight,
                                     frame.size.width, kToolbarHeight)];
    [contentView addSubview:toolbarView];

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
