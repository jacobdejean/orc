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
// Sidebar layout metrics. All coordinates are bottom-left origin; "top of
// sidebar" frames are computed from the sidebar's height at construction
// time and pinned with NSViewMinYMargin.
constexpr CGFloat kNavRowTopInset = 6;    // below the traffic lights
constexpr CGFloat kNavButtonSize = 24;
constexpr CGFloat kNavSymbolSize = 18;    // nav icon glyph size (pt)
constexpr CGFloat kNavButtonSpacing = 8;
constexpr CGFloat kNavRowLeftInset = 80;  // clears the traffic light cluster
constexpr CGFloat kAddressTopSpacing = 10;
constexpr CGFloat kAddressHeight = 36;
constexpr CGFloat kTabListTopSpacing = 16;
constexpr CGFloat kTabRowHeight = 28;
constexpr CGFloat kFaviconSize = 16;
constexpr CGFloat kFaviconLeftInset = 8;
constexpr CGFloat kCloseButtonSize = 16;
constexpr CGFloat kAddressTextInset = 8;
constexpr CGFloat kAddressIconSize = 16;  // magnifier glyph size (pt)
constexpr CGFloat kAddressIconGap = 5;
}  // namespace

// AddressField: a container view that draws the rounded dark pill and the
// magnifier icon, and hosts a real borderless NSTextField centered
// vertically inside it. Layout is done with plain views because modern
// AppKit ignores NSTextFieldCell text/titleRectForBounds overrides when
// drawing — the field-editor path alone can't be styled reliably.
@interface AddressFieldIconView : NSImageView
@end

@implementation AddressFieldIconView
- (NSView*)hitTest:(NSPoint)point {
  return nil;  // clicks fall through to the field
}
@end

@interface AddressField : NSView
- (NSTextField*)textField;
- (void)focusField;
@end

@implementation AddressField {
  NSTextField* field_;
}

- (instancetype)initWithFrame:(NSRect)frame {
  if ((self = [super initWithFrame:frame])) {
    NSImage* icon = [[NSImage imageWithSystemSymbolName:@"magnifyingglass"
                               accessibilityDescription:nil]
        imageWithSymbolConfiguration:[NSImageSymbolConfiguration
            configurationWithPointSize:kAddressIconSize
                                weight:NSFontWeightRegular]];
    AddressFieldIconView* iconView = [[AddressFieldIconView alloc]
        initWithFrame:NSMakeRect(kAddressTextInset,
                                 floor((NSHeight(frame) - kAddressIconSize) /
                                       2),
                                 kAddressIconSize, kAddressIconSize)];
    [iconView setImage:icon];
    [iconView setContentTintColor:theme::TextSecondary()];
    [iconView setAutoresizingMask:NSViewMaxXMargin];
    [self addSubview:iconView];

    NSFont* font = [NSFont systemFontOfSize:12 weight:NSFontWeightRegular];
    const CGFloat lineHeight =
        ceil([font ascender] - [font descender] + [font leading]);
    const CGFloat textX =
        kAddressTextInset + kAddressIconSize + kAddressIconGap;
    field_ = [[NSTextField alloc]
        initWithFrame:NSMakeRect(textX,
                                 floor((NSHeight(frame) - lineHeight) / 2),
                                 NSWidth(frame) - textX - kAddressTextInset,
                                 lineHeight)];
    [field_ setFont:font];
    [field_ setBezeled:NO];
    [field_ setDrawsBackground:NO];
    [field_ setEditable:YES];
    [field_ setFocusRingType:NSFocusRingTypeNone];
    [[field_ cell] setScrollable:YES];
    [[field_ cell] setWraps:NO];
    [field_ setAutoresizingMask:NSViewWidthSizable];
    [self addSubview:field_];
  }
  return self;
}

- (void)drawRect:(NSRect)dirtyRect {
  [theme::RowBackgroundHover() setFill];
  [[NSBezierPath bezierPathWithRoundedRect:[self bounds]
                                   xRadius:theme::CornerRadiusRow()
                                   yRadius:theme::CornerRadiusRow()] fill];
  [super drawRect:dirtyRect];
}

// Clicking the pill anywhere focuses the inner field.
- (void)mouseDown:(NSEvent*)event {
  [self focusField];
}

- (NSTextField*)textField {
  return field_;
}

- (void)focusField {
  [[self window] makeFirstResponder:field_];
}

// NSTextField API used by the sidebar, forwarded to the inner field.
- (void)setTarget:(id)target {
  [field_ setTarget:target];
}
- (void)setAction:(SEL)action {
  [field_ setAction:action];
}
- (void)setDelegate:(id<NSTextFieldDelegate>)delegate {
  [field_ setDelegate:delegate];
}
- (void)setPlaceholderString:(NSString*)placeholder {
  [field_ setPlaceholderString:placeholder];
}
- (void)setStringValue:(NSString*)value {
  [field_ setStringValue:value];
}
- (NSString*)stringValue {
  return [field_ stringValue];
}
- (NSText*)currentEditor {
  return [field_ currentEditor];
}
- (BOOL)abortEditing {
  return [field_ abortEditing];
}
@end

// Tab row button: handles hover background. Active state wins over hover.
@interface TabRowButton : NSButton
@property(nonatomic) BOOL active;
@property(nonatomic) BOOL hovered;
- (void)refreshBackground;
@end

@implementation TabRowButton
- (instancetype)initWithFrame:(NSRect)frame {
  if ((self = [super initWithFrame:frame])) {
    [self setWantsLayer:YES];
    [[self layer] setCornerRadius:theme::CornerRadiusRow()];
  }
  return self;
}
- (void)updateTrackingAreas {
  [super updateTrackingAreas];
  for (NSTrackingArea* area in [self trackingAreas]) {
    [self removeTrackingArea:area];
  }
  NSTrackingArea* area = [[NSTrackingArea alloc]
      initWithRect:[self bounds]
           options:NSTrackingMouseEnteredAndExited | NSTrackingActiveAlways
             owner:self
          userInfo:nil];
  [self addTrackingArea:area];
}
- (void)mouseEntered:(NSEvent*)event {
  _hovered = YES;
  [self refreshBackground];
}
- (void)mouseExited:(NSEvent*)event {
  _hovered = NO;
  [self refreshBackground];
}
- (void)refreshBackground {
  CGColorRef color =
      _active ? [theme::RowBackgroundActive() CGColor]
              : (_hovered ? [theme::RowBackgroundHover() CGColor] : nullptr);
  [[self layer] setBackgroundColor:color];
}
@end

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
  TabRowButton* row;
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
  AddressField* addressField_;
  NSView* rowsContainer_;       // holds tab rows + the New Tab row
  NSMutableArray<TabRow*>* rows_;
  TabRowButton* newTabRow_;
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
    backButton_ = [self makeButtonWithSymbol:@"arrow.left"
                                      action:@selector(goBack:)
                                       frame:NSMakeRect(x, y, kNavButtonSize,
                                                        kNavButtonSize)];
    x += kNavButtonSize + kNavButtonSpacing;
    forwardButton_ = [self makeButtonWithSymbol:@"arrow.right"
                                         action:@selector(goForward:)
                                          frame:NSMakeRect(x, y, kNavButtonSize,
                                                           kNavButtonSize)];
    x += kNavButtonSize + kNavButtonSpacing;
    reloadButton_ = [self makeButtonWithSymbol:@"arrow.clockwise"
                                        action:@selector(reloadPage:)
                                         frame:NSMakeRect(x, y, kNavButtonSize,
                                                          kNavButtonSize)];

    y -= kAddressTopSpacing + kAddressHeight;
    addressField_ = [[AddressField alloc]
        initWithFrame:NSMakeRect(pad, y, w - 2 * pad, kAddressHeight)];
    [addressField_ setPlaceholderString:@"Search or enter URL"];
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

- (NSButton*)makeButtonWithSymbol:(NSString*)symbolName
                             action:(SEL)action
                              frame:(NSRect)frame {
  TabRowButton* button = [[TabRowButton alloc] initWithFrame:frame];
  [button setTitle:@""];
  [button setBordered:NO];
  [button setTarget:self];
  [button setAction:action];
  [button setAutoresizingMask:NSViewMinYMargin];

  // The glyph is an NSImageView subview: NSButton's own image drawing
  // clips full-height symbols (arrow.clockwise) at the bottom edge.
  NSImage* image = [NSImage imageWithSystemSymbolName:symbolName
                             accessibilityDescription:nil];
  NSImageSymbolConfiguration* config = [NSImageSymbolConfiguration
      configurationWithPointSize:kNavSymbolSize
                          weight:NSFontWeightRegular];
  NSImageView* icon = [[NSImageView alloc]
      initWithFrame:NSMakeRect((frame.size.width - kNavSymbolSize) / 2,
                               (frame.size.height - kNavSymbolSize) / 2,
                               kNavSymbolSize, kNavSymbolSize)];
  [icon setImage:[image imageWithSymbolConfiguration:config]];
  [icon setContentTintColor:theme::TextSecondary()];
  [icon setAutoresizingMask:NSViewMinXMargin | NSViewMaxXMargin |
                            NSViewMinYMargin | NSViewMaxYMargin];
  [icon setTag:1];
  [button addSubview:icon];
  [view_ addSubview:button];
  return button;
}

// Helper: a row label sized to one line and vertically centered in the row.
- (NSTextField*)makeRowLabelWithX:(CGFloat)x width:(CGFloat)width {
  NSFont* font = theme::RowTitleFont();
  const CGFloat lineHeight =
      ceil([font ascender] - [font descender] + [font leading]);
  NSTextField* label = [[NSTextField alloc]
      initWithFrame:NSMakeRect(x, floor((kTabRowHeight - lineHeight) / 2),
                               width, lineHeight)];
  [label setEditable:NO];
  [label setBezeled:NO];
  [label setDrawsBackground:NO];
  [label setFont:font];
  [label setAlignment:NSTextAlignmentLeft];
  [label setLineBreakMode:NSLineBreakByTruncatingTail];
  [[label cell] setWraps:NO];
  [label setMaximumNumberOfLines:1];
  [label setAutoresizingMask:NSViewWidthSizable];
  return label;
}

// Helper: an SF Symbol image at the standard 16pt chrome size.
- (NSImage*)chromeSymbol:(NSString*)name {
  return [[NSImage imageWithSystemSymbolName:name
                    accessibilityDescription:nil]
      imageWithSymbolConfiguration:[NSImageSymbolConfiguration
          configurationWithPointSize:16
                              weight:NSFontWeightRegular]];
}

// "+ New Tab" row, laid out like a tab row: plus icon at the favicon spot,
// label where titles sit.
- (TabRowButton*)makeNewTabRow {
  newTabRow_ = [[TabRowButton alloc] initWithFrame:NSZeroRect];
  [newTabRow_ setTitle:@""];
  [newTabRow_ setBordered:NO];
  [newTabRow_ setTarget:self];
  [newTabRow_ setAction:@selector(newTab:)];
  [newTabRow_ setAutoresizingMask:NSViewWidthSizable | NSViewMinYMargin];

  NSImageView* icon = [[NSImageView alloc]
      initWithFrame:NSMakeRect(kFaviconLeftInset,
                               (kTabRowHeight - kFaviconSize) / 2,
                               kFaviconSize, kFaviconSize)];
  [icon setImage:[self chromeSymbol:@"plus"]];
  [icon setContentTintColor:theme::TextSecondary()];
  [icon setImageScaling:NSImageScaleProportionallyUpOrDown];
  [newTabRow_ addSubview:icon];

  const CGFloat titleX =
      kFaviconLeftInset + kFaviconSize + theme::SpacingS();
  NSTextField* label = [self makeRowLabelWithX:titleX
                                         width:300];  // clipped by the row
  [label setStringValue:@"New Tab"];
  [label setTextColor:theme::TextSecondary()];
  [newTabRow_ addSubview:label];
  return newTabRow_;
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
  tab->row = [[TabRowButton alloc] initWithFrame:NSMakeRect(0, 0, w,
                                                            kTabRowHeight)];
  [tab->row setTitle:@""];  // default NSButton title is literally "Button"
  [tab->row setBordered:NO];
  [tab->row setTarget:self];
  [tab->row setAction:@selector(selectTab:)];
  [tab->row setTag:tabId];
  [tab->row setAutoresizingMask:NSViewWidthSizable | NSViewMinYMargin];

  tab->faviconView = [[NSImageView alloc]
      initWithFrame:NSMakeRect(kFaviconLeftInset,
                               (kTabRowHeight - kFaviconSize) / 2,
                               kFaviconSize, kFaviconSize)];
  [tab->faviconView setImageScaling:NSImageScaleProportionallyUpOrDown];
  [tab->row addSubview:tab->faviconView];

  const CGFloat titleX =
      kFaviconLeftInset + kFaviconSize + theme::SpacingS();
  tab->label = [self makeRowLabelWithX:titleX
                                 width:w - titleX - kCloseButtonSize -
                                       theme::SpacingS()];
  [tab->label setTextColor:theme::TextPrimary()];
  [tab->label setStringValue:tab->title];
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
  [addressField_ focusField];
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
    [tab->row setActive:(tab->tabId == tabId)];
    [tab->row refreshBackground];
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
  NSImage* reloadImage = [[NSImage
        imageWithSystemSymbolName:loading ? @"xmark" : @"arrow.clockwise"
         accessibilityDescription:nil]
      imageWithSymbolConfiguration:[NSImageSymbolConfiguration
          configurationWithPointSize:kNavSymbolSize
                              weight:NSFontWeightRegular]];
  [(NSImageView*)[reloadButton_ viewWithTag:1] setImage:reloadImage];
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
  NSString* input = [addressField_ stringValue];
  std::string text = [input UTF8String];
  if (text.empty()) {
    return;
  }
  // URL-like input (has a scheme, or looks like a domain) navigates
  // directly; anything else falls back to a DuckDuckGo search.
  const bool hasScheme = text.find("://") != std::string::npos;
  const bool looksLikeDomain =
      [input rangeOfString:@"."].location != NSNotFound &&
      [input rangeOfString:@" "].location == NSNotFound;
  if (!hasScheme && !looksLikeDomain) {
    NSString* encoded = [input
        stringByAddingPercentEncodingWithAllowedCharacters:
            [NSCharacterSet URLQueryAllowedCharacterSet]];
    text = std::string("https://duckduckgo.com/?q=") + [encoded UTF8String];
  } else if (!hasScheme) {
    text = "https://" + text;
  }
  if (CefRefPtr<CefBrowser> browser = ExperimentClient::GetActiveBrowser()) {
    browser->GetMainFrame()->LoadURL(text);
  } else {
    // No tab open: the address bar acts as the entry point for the first
    // tab (Arc behaves the same).
    ExperimentClient::CreateTab(text);
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
    LayoutBrowserView(browser);
  }
}
