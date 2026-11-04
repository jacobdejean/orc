#include "experiment_app.h"

#import <Cocoa/Cocoa.h>

#include "include/cef_browser.h"
#include "include/cef_command_line.h"
#include "include/views/cef_browser_view.h"
#include "include/views/cef_window.h"
#include "include/wrapper/cef_helpers.h"

#include "toolbar.h"

namespace {

// Parent NSView* for the web content, set by main.mm before CefInitialize.
void* g_parent_view = nullptr;

// First browser created; used by main.mm's window delegate. Replaced by a
// proper browser registry once tabs exist.
CefRefPtr<CefBrowser> g_first_browser;

// When using the Views framework this creates a window hosting the browser.
// (Not used yet — main.mm creates the NSWindow directly — but kept here as
// the natural seam for the future chrome UI.)
class ExperimentWindowDelegate : public CefWindowDelegate {
 public:
  explicit ExperimentWindowDelegate(CefRefPtr<CefBrowserView> browser_view)
      : browser_view_(browser_view) {}

  void OnWindowCreated(CefRefPtr<CefWindow> window) override {
    window->AddChildView(browser_view_);
    window->Show();
  }

  void OnWindowDestroyed(CefRefPtr<CefWindow> window) override {
    browser_view_ = nullptr;
  }

  bool CanClose(CefRefPtr<CefWindow> window) override {
    if (browser_view_ && browser_view_->GetBrowser()) {
      browser_view_->GetBrowser()->GetHost()->TryCloseBrowser();
    }
    return true;
  }

  CefSize GetPreferredSize(CefRefPtr<CefView> view) override {
    return {1200, 800};
  }

 private:
  CefRefPtr<CefBrowserView> browser_view_;

  IMPLEMENT_REFCOUNTING(ExperimentWindowDelegate);
  DISALLOW_COPY_AND_ASSIGN(ExperimentWindowDelegate);
};

class ExperimentBrowserViewDelegate : public CefBrowserViewDelegate {
 public:
  ExperimentBrowserViewDelegate() = default;

  bool OnPopupBrowserViewCreated(CefRefPtr<CefBrowserView> browser_view,
                                 CefRefPtr<CefBrowserView> popup_browser_view,
                                 bool is_devtools) override {
    // Open popups in a new top-level window.
    CefWindow::CreateTopLevelWindow(
        new ExperimentWindowDelegate(popup_browser_view));
    return true;
  }

 private:
  IMPLEMENT_REFCOUNTING(ExperimentBrowserViewDelegate);
  DISALLOW_COPY_AND_ASSIGN(ExperimentBrowserViewDelegate);
};

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
  // No tab/window management yet: open popups in the current view.
  if (!target_url.empty()) {
    frame->LoadURL(target_url);
  }
  return true;  // Suppress the popup.
}

void ExperimentClient::OnAfterCreated(CefRefPtr<CefBrowser> browser) {
  CEF_REQUIRE_UI_THREAD();
  if (!g_first_browser) {
    g_first_browser = browser;
  }
  browser_count_++;

  // Let the web content view follow window resizes, leaving room for the
  // toolbar pinned to the top of the contentView.
  NSView* browserView =
      (__bridge NSView*)browser->GetHost()->GetWindowHandle();
  [browserView setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
  NSRect bounds = [[browserView superview] bounds];
  [browserView setFrame:NSMakeRect(0, 0, bounds.size.width,
                                   bounds.size.height - kToolbarHeight)];
}

void ExperimentClient::OnAddressChange(CefRefPtr<CefBrowser> browser,
                                       CefRefPtr<CefFrame> frame,
                                       const CefString& url) {
  CEF_REQUIRE_UI_THREAD();
  if (frame->IsMain()) {
    ToolbarSetAddressText(url.ToString());
  }
}

void ExperimentClient::OnTitleChange(CefRefPtr<CefBrowser> browser,
                                     const CefString& title) {
  CEF_REQUIRE_UI_THREAD();
  NSView* browserView =
      (__bridge NSView*)browser->GetHost()->GetWindowHandle();
  NSString* nsTitle =
      [NSString stringWithUTF8String:title.ToString().c_str()];
  [[browserView window] setTitle:nsTitle ?: @"Experiment"];
}

void ExperimentClient::OnLoadingStateChange(CefRefPtr<CefBrowser> browser,
                                            bool isLoading,
                                            bool canGoBack,
                                            bool canGoForward) {
  CEF_REQUIRE_UI_THREAD();
  ToolbarSetLoadingState(isLoading, canGoBack, canGoForward);
}

// static
CefRefPtr<CefBrowser> ExperimentClient::GetFirstBrowserForTesting() {
  return g_first_browser;
}

bool ExperimentClient::DoClose(CefRefPtr<CefBrowser> browser) {
  CEF_REQUIRE_UI_THREAD();
  return false;  // Allow the close.
}

void ExperimentClient::OnBeforeClose(CefRefPtr<CefBrowser> browser) {
  CEF_REQUIRE_UI_THREAD();
  if (g_first_browser && g_first_browser->IsSame(browser)) {
    g_first_browser = nullptr;
  }
  if (--browser_count_ == 0) {
    CefQuitMessageLoop();
  }
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

  const std::string url = "https://example.com";

  CefRefPtr<CefCommandLine> command_line =
      CefCommandLine::GetGlobalCommandLine();
  const bool use_views = command_line->HasSwitch("use-views");

  CefRefPtr<ExperimentClient> client(new ExperimentClient());

  if (use_views) {
    // Views-framework path: CEF manages the window.
    CefBrowserSettings browser_settings;
    CefRefPtr<CefBrowserView> browser_view = CefBrowserView::CreateBrowserView(
        client, url, browser_settings, nullptr, nullptr,
        new ExperimentBrowserViewDelegate());
    CefWindow::CreateTopLevelWindow(
        new ExperimentWindowDelegate(browser_view));
  } else {
    // Embed the web view as a child of the NSWindow's contentView (set by
    // main.mm). Future native chrome will shrink/reposition this view.
    CefWindowInfo window_info;
    window_info.SetAsChild(g_parent_view, CefRect(0, 0, 1200, 800));
    CefBrowserSettings browser_settings;
    CefBrowserHost::CreateBrowser(window_info, client, url, browser_settings,
                                  nullptr, nullptr);
  }
}

void SetParentViewForBrowser(void* view) {
  g_parent_view = view;
}
