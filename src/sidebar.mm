// Native sidebar chrome: nav buttons, URL field, and the tab list.
// Talks to CEF through ExperimentClient's static tab API. The bridge
// functions at the bottom are called by the CEF client on the UI thread
// (same thread as the AppKit run loop), so direct view updates are safe.

#import <Cocoa/Cocoa.h>

#include "experiment_app.h"
#include "sidebar.h"
#include "theme.h"

// ---------------------------------------------------------------------------
// Sidebar layout metrics. Everything visual lives here so the chrome is easy
// to tweak: change a constant, rebuild, done. Coordinates are bottom-left
// origin (AppKit default), so "top of sidebar" frames are computed from the
// sidebar's height at construction time and pinned with NSViewMinYMargin.
// ---------------------------------------------------------------------------
namespace {
constexpr CGFloat kNavRowTopInset = 10;    // below the traffic lights
constexpr CGFloat kNavButtonSize = 24;
constexpr CGFloat kNavButtonSpacing = 6;
constexpr CGFloat kNavRowLeftInset = 76;   // clears the traffic light cluster
constexpr CGFloat kAddressTopSpacing = 8;  // gap between nav row and field
constexpr CGFloat kAddressHeight = 28;
constexpr CGFloat kTabListTopSpacing = 16;
constexpr CGFloat kTabRowHeight = 28;
constexpr CGFloat kFaviconSize = 16;
constexpr CGFloat kFaviconLeftInset = 6;
constexpr CGFloat kCloseButtonSize = 16;
}  // namespace

// Sidebar background view: empty areas drag the window (like Arc), while
// clicks on actual controls (subviews) pass through normally.
@interface SidebarBackgroundView : NSVisualEffectView
@end

@implementation SidebarBackgroundView
- (void)mouseDown:(NSEvent*)event {
  [[self window] performWindowDragWithEvent:event];
}
@end

// Model + views for one tab row. The row itself is a transparent NSButton so
// the whole row is clickable; favicon/title/close are subviews.
@interface TabRow : NSObject {
 @public
  int tabId;
  NSString* title;
  NSString* faviconURL;  // last favicon URL, to avoid refetching
  NSButton* row;
  NSImageView* faviconView;
  NSTextField* label;
  NSButton* closeButton;
}
@end

@implementation TabRow
@end

@interface ExperimentSidebar : NSObject <NSTextFieldDelegate> {
  SidebarBackgroundView* view_;
  NSButton* backButton_;
  NSButton* forwardButton_;
  NSButton* reloadButton_;
  NSTextField* addressField_;
  NSView* rowsContainer_;       // holds tab rows + the New Tab row
  NSMutableArray<TabRow*>* rows_;
  NSView* newTabRow_;
  int activeTabId_;
  NSString* lastCommittedURL_;  // for Esc-revert in the address field
}
- (instancetype)initWithHeight:(CGFloat)height;
- (NSView*)view;
- (void)setAddressText:(NSString*)url;
- (void)setLoadingState:(BOOL)loading
             canGoBack:(BOOL)canGoBack
          canGoForward:(BOOL)canGoForward;
- (void)addTabWithId:(int)tabId;
- (void)removeTabWithId:(int)tabId;
- (void)setActiveTabWithId:(int)tabId;
- (void)setTitle:(NSString*)title forTab:(int)tabId;
- (void)setFaviconURL:(NSString*)url forTab:(int)tabId;
@end

@implementation ExperimentSidebar

- (instancetype)initWithHeight:(CGFloat)height {
  if ((self = [super init])) {
    const CGFloat w = kSidebarWidth;
    const CGFloat pad = theme::SpacingM();
    activeTabId_ = -1;
    rows_ = [[NSMutableArray alloc] init];

    view_ = [[SidebarBackgroundView alloc]
        initWithFrame:NSMakeRect(0, 0, w, height)];
    [view_ setMaterial:NSVisualEffectMaterialSidebar];
    [view_ setBlendingMode:NSVisualEffectBlendingModeBehindWindow];
    // Pinned to the left edge, stretching with window height.
    [view_ setAutoresizingMask:NSViewHeightSizable | NSViewMaxXMargin];

    // All sidebar contents are top-anchored: flexible bottom margin keeps
    // them glued to the top when the window resizes.
    const NSUInteger topAnchored = NSViewMinYMargin;
    CGFloat y = height - kNavRowTopInset - kNavButtonSize;

    CGFloat x = kNavRowLeftInset;
    backButton_ = [self makeButtonWithTitle:@"◀"
                                     action:@selector(goBack:)
                                      frame:NSMakeRect(x, y, kNavButtonSize,
                                                       kNavButtonSize)];
    x += kNavButtonSize + kNavButtonSpacing;
    forwardButton_ = [self makeButtonWithTitle:@"▶"
                                        action:@selector(goForward:)
                                         frame:NSMakeRect(x, y, kNavButtonSize,
                                                          kNavButtonSize)];
    x += kNavButtonSize + kNavButtonSpacing;
    reloadButton_ = [self makeButtonWithTitle:@"⟳"
                                       action:@selector(reloadPage:)
                                        frame:NSMakeRect(x, y, kNavButtonSize,
                                                         kNavButtonSize)];

    y -= kAddressTopSpacing + kAddressHeight;
    addressField_ = [[NSTextField alloc]
        initWithFrame:NSMakeRect(pad, y, w - 2 * pad, kAddressHeight)];
    [addressField_ setBezelStyle:NSTextFieldRoundedBezel];
    [addressField_ setPlaceholderString:@"Search or enter address"];
    [addressField_ setTarget:self];
    [addressField_ setAction:@selector(addressEntered:)];
    [addressField_ setDelegate:self];
    [addressField_ setAutoresizingMask:NSViewWidthSizable | topAnchored];
    [view_ addSubview:addressField_];

    // Tab rows live in a container that fills the sidebar below the address
    // field; rows are laid out top-down inside it by relayoutRows.
    const CGFloat containerTop = y - kTabListTopSpacing;
    rowsContainer_ = [[NSView alloc]
        initWithFrame:NSMakeRect(pad, 0, w - 2 * pad, containerTop)];
    [rowsContainer_ setAutoresizingMask:NSViewWidthSizable |
                                        NSViewHeightSizable];
    [view_ addSubview:rowsContainer_];

    // "+ New Tab" row at the top of the list when empty; relayoutRows keeps
    // it pinned below the last tab row.
    newTabRow_ = [self makeNewTabRow];
    [rowsContainer_ addSubview:newTabRow_];
    [self relayoutRows];
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
  [button setAutoresizingMask:NSViewMinYMargin];
  [view_ addSubview:button];
  return button;
}

- (NSView*)makeNewTabRow {
  NSButton* row = [[NSButton alloc] initWithFrame:NSZeroRect];
  [row setTitle:@"+  New Tab"];
  [row setBordered:NO];
  [row setAlignment:NSTextAlignmentLeft];
  [row setFont:theme::RowTitleFont()];
  [row setContentTintColor:theme::TextSecondary()];
  [row setTarget:self];
  [row setAction:@selector(newTab:)];
  [row setAutoresizingMask:NSViewWidthSizable | NSViewMinYMargin];
  return row;
}

- (NSView*)view {
  return view_;
}

// --- Tab list ---------------------------------------------------------------

- (TabRow*)rowForTab:(int)tabId {
  for (TabRow* row in rows_) {
    if (row->tabId == tabId) {
      return row;
    }
  }
  return nil;
}

- (void)addTabWithId:(int)tabId {
  TabRow* tab = [[TabRow alloc] init];
  tab->tabId = tabId;
  tab->title = @"New Tab";

  const CGFloat w = [rowsContainer_ bounds].size.width;
  tab->row = [[NSButton alloc] initWithFrame:NSMakeRect(0, 0, w,
                                                        kTabRowHeight)];
  [tab->row setTitle:@""];  // default NSButton title is literally "Button"
  [tab->row setBordered:NO];
  [tab->row setTarget:self];
  [tab->row setAction:@selector(selectTab:)];
  [tab->row setTag:tabId];
  [tab->row setWantsLayer:YES];
  [[tab->row layer] setCornerRadius:theme::CornerRadiusRow()];
  [tab->row setAutoresizingMask:NSViewWidthSizable | NSViewMinYMargin];

  tab->faviconView = [[NSImageView alloc]
      initWithFrame:NSMakeRect(kFaviconLeftInset,
                               (kTabRowHeight - kFaviconSize) / 2,
                               kFaviconSize, kFaviconSize)];
  [tab->faviconView setImageScaling:NSImageScaleProportionallyUpOrDown];
  [tab->row addSubview:tab->faviconView];

  const CGFloat titleX =
      kFaviconLeftInset + kFaviconSize + theme::SpacingS();
  tab->label = [[NSTextField alloc]
      initWithFrame:NSMakeRect(titleX, 0,
                               w - titleX - kCloseButtonSize -
                                   theme::SpacingS(),
                               kTabRowHeight)];
  [tab->label setEditable:NO];
  [tab->label setBezeled:NO];
  [tab->label setDrawsBackground:NO];
  [tab->label setFont:theme::RowTitleFont()];
  [tab->label setTextColor:theme::TextPrimary()];
  [tab->label setAlignment:NSTextAlignmentLeft];
  [tab->label setStringValue:tab->title];
  [tab->label setLineBreakMode:NSLineBreakByTruncatingTail];
  [[tab->label cell] setWraps:NO];
  [tab->label setMaximumNumberOfLines:1];
  [tab->label setAutoresizingMask:NSViewWidthSizable];
  [tab->row addSubview:tab->label];

  tab->closeButton = [[NSButton alloc]
      initWithFrame:NSMakeRect(w - kCloseButtonSize - theme::SpacingXS(),
                               (kTabRowHeight - kCloseButtonSize) / 2,
                               kCloseButtonSize, kCloseButtonSize)];
  [tab->closeButton setTitle:@"✕"];
  [tab->closeButton setBordered:NO];
  [tab->closeButton setFont:[NSFont systemFontOfSize:10]];
  [tab->closeButton setContentTintColor:theme::TextSecondary()];
  [tab->closeButton setTarget:self];
  [tab->closeButton setAction:@selector(closeTab:)];
  [tab->closeButton setTag:tabId];
  [tab->closeButton setAutoresizingMask:NSViewMinXMargin];
  [tab->row addSubview:tab->closeButton];

  [rows_ addObject:tab];
  [rowsContainer_ addSubview:tab->row];
  [self relayoutRows];
}

- (void)focusAddressField {
  [[addressField_ window] makeFirstResponder:addressField_];
}

- (void)removeTabWithId:(int)tabId {
  TabRow* tab = [self rowForTab:tabId];
  if (!tab) {
    return;
  }
  [tab->row removeFromSuperview];
  [rows_ removeObject:tab];
  [self relayoutRows];
}

- (void)setActiveTabWithId:(int)tabId {
  activeTabId_ = tabId;
  // Switching tabs ends any in-progress URL edit so the field can sync to
  // the newly active tab.
  if ([addressField_ currentEditor] != nil) {
    [addressField_ abortEditing];
  }
  for (TabRow* tab in rows_) {
    const BOOL active = (tab->tabId == tabId);
    CGColorRef color =
        active ? [theme::RowBackgroundActive() CGColor] : nullptr;
    [[tab->row layer] setBackgroundColor:color];
  }
}

- (void)setTitle:(NSString*)title forTab:(int)tabId {
  TabRow* tab = [self rowForTab:tabId];
  if (tab) {
    tab->title = [title copy];
    [tab->label setStringValue:tab->title];
  }
}

- (void)setFaviconURL:(NSString*)url forTab:(int)tabId {
  TabRow* tab = [self rowForTab:tabId];
  if (!tab || [url isEqualToString:tab->faviconURL]) {
    return;
  }
  tab->faviconURL = [url copy];
  // Fetch off the UI thread. Fine for an experiment; a real app would cache
  // to disk and key icons by origin rather than URL.
  NSURL* nsurl = [NSURL URLWithString:url];
  if (!nsurl) {
    return;
  }
  [[[NSURLSession sharedSession]
      dataTaskWithURL:nsurl
      completionHandler:^(NSData* data, NSURLResponse*, NSError*) {
        NSImage* image = data ? [[NSImage alloc] initWithData:data] : nil;
        if (!image) {
          return;
        }
        dispatch_async(dispatch_get_main_queue(), ^{
          [tab->faviconView setImage:image];
        });
      }] resume];
}

// Rows stack from the top of the container downward; the New Tab row sits
// below the last tab row.
- (void)relayoutRows {
  const CGFloat h = [rowsContainer_ bounds].size.height;
  const CGFloat w = [rowsContainer_ bounds].size.width;
  CGFloat y = h;
  for (TabRow* tab in rows_) {
    y -= kTabRowHeight;
    [tab->row setFrame:NSMakeRect(0, y, w, kTabRowHeight)];
  }
  y -= kTabRowHeight + theme::SpacingXS();
  [newTabRow_ setFrame:NSMakeRect(0, y, w, kTabRowHeight)];
}

// --- Active-tab state ---------------------------------------------------------

- (void)setAddressText:(NSString*)url {
  // Don't stomp on text the user is actively editing.
  if ([addressField_ currentEditor] == nil) {
    [addressField_ setStringValue:url];
    lastCommittedURL_ = [url copy];
  }
}

- (void)setLoadingState:(BOOL)loading
             canGoBack:(BOOL)canGoBack
          canGoForward:(BOOL)canGoForward {
  [backButton_ setEnabled:canGoBack];
  [forwardButton_ setEnabled:canGoForward];
  [reloadButton_ setTitle:loading ? @"✕" : @"⟳"];
}

// Clicking into the field selects everything (Arc/Chrome behavior).
- (void)controlTextDidBeginEditing:(NSNotification*)notification {
  dispatch_async(dispatch_get_main_queue(), ^{
    [[addressField_ currentEditor] selectAll:nil];
  });
}

// Esc reverts the field to the committed URL.
- (BOOL)control:(NSControl*)control
               textView:(NSTextView*)textView
    doCommandBySelector:(SEL)commandSelector {
  if (commandSelector == @selector(cancelOperation:)) {
    if (lastCommittedURL_) {
      [addressField_ setStringValue:lastCommittedURL_];
    }
    [control abortEditing];
    return YES;
  }
  return NO;
}

// --- Actions (native UI → CEF) -------------------------------------------------

- (void)goBack:(id)sender {
  if (CefRefPtr<CefBrowser> browser = ExperimentClient::GetActiveBrowser()) {
    browser->GoBack();
  }
}

- (void)goForward:(id)sender {
  if (CefRefPtr<CefBrowser> browser = ExperimentClient::GetActiveBrowser()) {
    browser->GoForward();
  }
}

- (void)reloadPage:(id)sender {
  if (CefRefPtr<CefBrowser> browser = ExperimentClient::GetActiveBrowser()) {
    if (browser->IsLoading()) {
      browser->StopLoad();
    } else {
      browser->Reload();
    }
  }
}

- (void)newTab:(id)sender {
  ExperimentClient::CreateTab("about:blank");
}

- (void)selectTab:(id)sender {
  ExperimentClient::ActivateTab((int)[sender tag]);
}

- (void)closeTab:(id)sender {
  ExperimentClient::CloseTabById((int)[sender tag]);
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
  if (CefRefPtr<CefBrowser> browser = ExperimentClient::GetActiveBrowser()) {
    browser->GetMainFrame()->LoadURL(text);
  }
}

@end

// --- Bridge (called by the CEF client; see sidebar.h) --------------------------

static ExperimentSidebar* g_sidebar = nil;

void SidebarCreate(NSView* contentView, CGFloat height) {
  g_sidebar = [[ExperimentSidebar alloc] initWithHeight:height];
  [contentView addSubview:[g_sidebar view]];
}

void SidebarTabAdded(int browser_id) {
  [g_sidebar addTabWithId:browser_id];
}

void SidebarTabRemoved(int browser_id) {
  [g_sidebar removeTabWithId:browser_id];
}

void SidebarSetActiveTab(int browser_id) {
  [g_sidebar setActiveTabWithId:browser_id];
}

void SidebarTabSetTitle(int browser_id, const std::string& title) {
  [g_sidebar setTitle:[NSString stringWithUTF8String:title.c_str()]
               forTab:browser_id];
}

void SidebarTabSetFaviconURL(int browser_id, const std::string& icon_url) {
  [g_sidebar setFaviconURL:[NSString stringWithUTF8String:icon_url.c_str()]
                    forTab:browser_id];
}

void SidebarSetAddressText(const std::string& url) {
  [g_sidebar setAddressText:[NSString stringWithUTF8String:url.c_str()]];
}

void SidebarSetLoadingState(bool is_loading, bool can_go_back,
                            bool can_go_forward) {
  [g_sidebar setLoadingState:is_loading
                  canGoBack:can_go_back
               canGoForward:can_go_forward];
}

bool SidebarIsHidden() {
  return [[g_sidebar view] isHidden];
}

void SidebarFocusAddressField() {
  [g_sidebar focusAddressField];
}

// Show/hide the sidebar; the active web view expands to fill the space.
// NOTE: with the sidebar hidden, the traffic lights float over the web
// content (Arc shows a floating control cluster instead — polish item).
void SidebarToggleHidden() {
  NSView* sidebarView = [g_sidebar view];
  BOOL hiding = ![sidebarView isHidden];
  [sidebarView setHidden:hiding];
  if (CefRefPtr<CefBrowser> browser = ExperimentClient::GetActiveBrowser()) {
    NSView* browserView =
        (__bridge NSView*)browser->GetHost()->GetWindowHandle();
    NSRect bounds = [[browserView superview] bounds];
    CGFloat x = hiding ? 0 : kSidebarWidth;
    [browserView setFrame:NSMakeRect(x, 0, bounds.size.width - x,
                                     bounds.size.height)];
  }
}
