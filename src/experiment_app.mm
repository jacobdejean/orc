#include "experiment_app.h"

#import <Cocoa/Cocoa.h>

#include <map>

#include "include/cef_browser.h"
#include "include/cef_command_line.h"
#include "include/cef_parser.h"
#include "include/wrapper/cef_helpers.h"

#include "sidebar.h"

namespace {

// Parent NSView* for the web content, set by main.mm before CefInitialize.
void* g_parent_view = nullptr;

// --- Tab registry (UI thread only) -------------------------------------------
std::map<int, CefRefPtr<CefBrowser>> g_tabs;
int g_active_tab = -1;
bool g_terminating = false;

// One client instance shared by all tabs; keeps handler wiring trivial.
CefRefPtr<ExperimentClient> g_client;

// Lays out a browser's native view in the content area (right of the
// sidebar, or full width when the sidebar is hidden) and sizes it to track
// window resizes.
void LayoutBrowserView(CefRefPtr<CefBrowser> browser) {
  NSView* browserView =
      (__bridge NSView*)browser->GetHost()->GetWindowHandle();
  [browserView setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
  NSRect bounds = [[browserView superview] bounds];
  CGFloat x = SidebarIsHidden() ? 0 : kSidebarWidth;
  [browserView setFrame:NSMakeRect(x, 0, bounds.size.width - x,
                                   bounds.size.height)];
}

NSView* BrowserNSView(CefRefPtr<CefBrowser> browser) {
  return (__bridge NSView*)browser->GetHost()->GetWindowHandle();
}

}  // namespace

bool ExperimentClient::OnBeforePopup(
    CefRefPtr<CefBrowser> browser,
    CefRefPtr<CefFrame> frame,
    int popup_id,
    const CefString& target_url,
    const CefString& target_frame_name,
    WindowOpenDisposition target_disposition,
    bool user_gesture,
    const CefPopupFeatures& popupFeatures,
    CefWindowInfo& windowInfo,
    CefRefPtr<CefClient>& client,
    CefBrowserSettings& settings,
    CefRefPtr<CefDictionaryValue>& extra_info,
    bool* no_javascript_access) {
  CEF_REQUIRE_UI_THREAD();
  // Popups open as new tabs.
  if (!target_url.empty()) {
    CreateTab(target_url.ToString());
  }
  return true;  // Suppress the popup window.
}

void ExperimentClient::OnAfterCreated(CefRefPtr<CefBrowser> browser) {
  CEF_REQUIRE_UI_THREAD();
  const int id = browser->GetIdentifier();
  g_tabs[id] = browser;
  LayoutBrowserView(browser);
  SidebarTabAdded(id);
  // New tabs take focus, Arc-style.
  ActivateTab(id);
  // A blank new tab wants a URL: focus the address field (typing replaces
  // the selected "about:blank").
  if (CefRefPtr<CefFrame> frame = browser->GetMainFrame()) {
    if (frame->GetURL().ToString() == "about:blank") {
      SidebarFocusAddressField();
    }
  }
}

bool ExperimentClient::DoClose(CefRefPtr<CefBrowser> browser) {
  CEF_REQUIRE_UI_THREAD();
  // Complete the browser close by tearing down the native view ourselves
  // (step 9 of the DoClose contract): the browser's teardown is triggered by
  // DESTRUCTION of its native view, so removing it from the view hierarchy
  // here is what actually lets OnBeforeClose fire.
  [BrowserNSView(browser) removeFromSuperview];
  return false;  // Allow the close.
}

void ExperimentClient::OnBeforeClose(CefRefPtr<CefBrowser> browser) {
  CEF_REQUIRE_UI_THREAD();
  const int id = browser->GetIdentifier();
  const bool was_active = (id == g_active_tab);
  g_tabs.erase(id);
  SidebarTabRemoved(id);

  if (was_active) {
    g_active_tab = -1;
    if (!g_tabs.empty()) {
      // Activate the most recently created remaining tab.
      ActivateTab(g_tabs.rbegin()->first);
    }
  }

  if (g_tabs.empty()) {
    StartViewSetVisible(true);
    if (g_terminating) {
      CefQuitMessageLoop();
    }
  }
}

void ExperimentClient::OnAddressChange(CefRefPtr<CefBrowser> browser,
                                       CefRefPtr<CefFrame> frame,
                                       const CefString& url) {
  CEF_REQUIRE_UI_THREAD();
  if (frame->IsMain() && IsActive(browser)) {
    SidebarSetAddressText(url.ToString());
  }
}

void ExperimentClient::OnTitleChange(CefRefPtr<CefBrowser> browser,
                                     const CefString& title) {
  CEF_REQUIRE_UI_THREAD();
  SidebarTabSetTitle(browser->GetIdentifier(), title.ToString());
  if (IsActive(browser)) {
    NSString* nsTitle =
        [NSString stringWithUTF8String:title.ToString().c_str()];
    [BrowserNSView(browser).window setTitle:nsTitle ?: @"Experiment"];
  }
}

void ExperimentClient::OnFaviconURLChange(
    CefRefPtr<CefBrowser> browser,
    const std::vector<CefString>& icon_urls) {
  CEF_REQUIRE_UI_THREAD();
  if (!icon_urls.empty()) {
    SidebarTabSetFaviconURL(browser->GetIdentifier(),
                            icon_urls[0].ToString());
  }
}

void ExperimentClient::OnLoadingStateChange(CefRefPtr<CefBrowser> browser,
                                            bool isLoading,
                                            bool canGoBack,
                                            bool canGoForward) {
  CEF_REQUIRE_UI_THREAD();
  if (IsActive(browser)) {
    SidebarSetLoadingState(isLoading, canGoBack, canGoForward);
  }
}

void ExperimentClient::OnLoadError(CefRefPtr<CefBrowser> browser,
                                   CefRefPtr<CefFrame> frame,
                                   ErrorCode errorCode,
                                   const CefString& errorText,
                                   const CefString& failedUrl) {
  CEF_REQUIRE_UI_THREAD();
  // Ignore aborted loads (user stopped the load, or a navigation raced this
  // one) and sub-frame errors.
  if (errorCode == ERR_ABORTED || !frame->IsMain()) {
    return;
  }
  // Without this, a failed load just leaves a blank view. Show a minimal
  // inline error page so the state is visible instead of silent.
  std::string html =
      "<html><body style='background:#1e1e1e;color:#ccc;font:14px "
      "\"-apple-system\";display:flex;justify-content:center;padding-top:20%'>"
      "<div><b>Page failed to load</b><br><br>" +
      errorText.ToString() + "<br>" + failedUrl.ToString() +
      "</div></body></html>";
  // Percent-encode: a raw '#' would truncate the data URL at the fragment.
  frame->LoadURL("data:text/html;charset=utf-8," +
                 CefURIEncode(html, false).ToString());
}

// --- Tab registry implementation ---------------------------------------------

// static
void ExperimentClient::CreateTab(const std::string& url) {
  CEF_REQUIRE_UI_THREAD();
  DCHECK(g_parent_view);
  CefWindowInfo window_info;
  window_info.SetAsChild(g_parent_view, CefRect(0, 0, 1, 1));
  CefBrowserSettings browser_settings;
  CefBrowserHost::CreateBrowser(window_info, g_client, url, browser_settings,
                                nullptr, nullptr);
}

// static
void ExperimentClient::CloseTabById(int browser_id) {
  CEF_REQUIRE_UI_THREAD();
  auto it = g_tabs.find(browser_id);
  if (it != g_tabs.end()) {
    // DoClose (called synchronously from here) removes the native view,
    // which completes the teardown and triggers OnBeforeClose.
    it->second->GetHost()->CloseBrowser(false);
  }
}

// static
void ExperimentClient::ActivateTab(int browser_id) {
  CEF_REQUIRE_UI_THREAD();
  auto it = g_tabs.find(browser_id);
  if (it == g_tabs.end()) {
    return;
  }
  g_active_tab = browser_id;
  CefRefPtr<CefBrowser> browser = it->second;

  for (const auto& [id, other] : g_tabs) {
    [BrowserNSView(other) setHidden:(id != browser_id)];
  }
  // Re-layout in case the sidebar was toggled while this tab was hidden.
  LayoutBrowserView(browser);

  SidebarSetActiveTab(browser_id);
  StartViewSetVisible(false);

  // Sync sidebar state to the newly active tab.
  if (CefRefPtr<CefFrame> frame = browser->GetMainFrame()) {
    SidebarSetAddressText(frame->GetURL().ToString());
  }
  SidebarSetLoadingState(browser->IsLoading(), browser->CanGoBack(),
                         browser->CanGoForward());
  browser->GetHost()->SetFocus(true);
}

// static
CefRefPtr<CefBrowser> ExperimentClient::GetActiveBrowser() {
  CEF_REQUIRE_UI_THREAD();
  auto it = g_tabs.find(g_active_tab);
  return it != g_tabs.end() ? it->second : nullptr;
}

// static
void ExperimentClient::CloseAllBrowsers() {
  CEF_REQUIRE_UI_THREAD();
  for (const auto& [id, browser] : g_tabs) {
    browser->GetHost()->CloseBrowser(false);
  }
}

// static
bool ExperimentClient::HasTabs() {
  return !g_tabs.empty();
}

// static
void ExperimentClient::SetTerminating() {
  g_terminating = true;
}

bool ExperimentClient::IsActive(CefRefPtr<CefBrowser> browser) const {
  return browser->GetIdentifier() == g_active_tab;
}

void ExperimentApp::OnBeforeCommandLineProcessing(
    const CefString& process_type,
    CefRefPtr<CefCommandLine> command_line) {
  if (process_type.empty()) {  // browser process only
    // Don't touch the real Keychain while iterating: the app is ad-hoc
    // signed, so its signature changes every build and Keychain would
    // re-prompt for "confidential information" access each time.
    command_line->AppendSwitch("use-mock-keychain");
  }
}

void ExperimentApp::OnContextInitialized() {
  CEF_REQUIRE_UI_THREAD();
  g_client = new ExperimentClient();
  // Intentionally create NO browser here: the window starts empty (native
  // start view), and the first tab is created by the user (⌘T / + New Tab).
  // Exception: EXPERIMENT_START_URL opens tabs for testing — comma-separate
  // multiple URLs to spawn several tabs at launch.
  //   EXPERIMENT_START_URL=https://github.com,https://example.com
  const char* env_url = std::getenv("EXPERIMENT_START_URL");
  if (env_url && env_url[0]) {
    std::string urls = env_url;
    size_t pos = 0;
    while (pos <= urls.size()) {
      size_t comma = urls.find(',', pos);
      std::string url = urls.substr(pos, comma == std::string::npos
                                           ? std::string::npos
                                           : comma - pos);
      if (!url.empty()) {
        ExperimentClient::CreateTab(url);
      }
      if (comma == std::string::npos) {
        break;
      }
      pos = comma + 1;
    }
  }
}

void SetParentViewForBrowser(void* view) {
  g_parent_view = view;
}
