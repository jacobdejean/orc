#import <Cocoa/Cocoa.h>

#include "include/cef_app.h"
#include "include/cef_application_mac.h"
#include "include/wrapper/cef_helpers.h"
#include "include/wrapper/cef_library_loader.h"

#include "experiment_app.h"

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
    browser->GetHost()->CloseBrowser(false);
  } else {
    CefQuitMessageLoop();
  }
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

    // The web content renders into this view. Native chrome (tab strip,
    // sidebar) will later be added as sibling subviews of the contentView.
    NSView* contentView = [window contentView];
    SetParentViewForBrowser(contentView);

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

    CefRunMessageLoop();
    CefShutdown();
  }
  return 0;
}
