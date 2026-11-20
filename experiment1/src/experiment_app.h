#pragma once

#include "include/cef_app.h"
#include "include/cef_client.h"
#include "include/cef_display_handler.h"
#include "include/cef_life_span_handler.h"
#include "include/cef_load_handler.h"

// Frames the browser's native view within the content area, honoring
// sidebar visibility and the kWebViewPadding card inset (sidebar.h).
void LayoutBrowserView(CefRefPtr<CefBrowser> browser);

// Browser client: owns per-browser lifecycle callbacks plus the display/load
// callbacks that drive the native sidebar. One shared instance serves all
// tabs (see g_client in experiment_app.mm).
//
// Tab registry: browsers are keyed by CefBrowser::GetIdentifier(). The
// static methods below are the entire tab API used by the native chrome
// (sidebar, menus). All must be called on the UI thread.
class ExperimentClient : public CefClient,
                         public CefLifeSpanHandler,
                         public CefDisplayHandler,
                         public CefLoadHandler {
 public:
  ExperimentClient() = default;

  CefRefPtr<CefLifeSpanHandler> GetLifeSpanHandler() override { return this; }
  CefRefPtr<CefDisplayHandler> GetDisplayHandler() override { return this; }
  CefRefPtr<CefLoadHandler> GetLoadHandler() override { return this; }

  // --- Tab registry (UI thread) -------------------------------------------
  static void CreateTab(const std::string& url);
  static void CloseTabById(int browser_id);
  static void ActivateTab(int browser_id);
  static CefRefPtr<CefBrowser> GetActiveBrowser();
  static void CloseAllBrowsers();
  static bool HasTabs();
  // Once set, the last browser close quits the message loop. Needed because
  // "no tabs" is a normal state (empty start) and must not quit the app.
  static void SetTerminating();

  // CefLifeSpanHandler:
  bool OnBeforePopup(CefRefPtr<CefBrowser> browser,
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
                     bool* no_javascript_access) override;
  void OnAfterCreated(CefRefPtr<CefBrowser> browser) override;
  bool DoClose(CefRefPtr<CefBrowser> browser) override;
  void OnBeforeClose(CefRefPtr<CefBrowser> browser) override;

  // CefDisplayHandler:
  void OnAddressChange(CefRefPtr<CefBrowser> browser,
                       CefRefPtr<CefFrame> frame,
                       const CefString& url) override;
  void OnTitleChange(CefRefPtr<CefBrowser> browser,
                     const CefString& title) override;
  void OnFaviconURLChange(
      CefRefPtr<CefBrowser> browser,
      const std::vector<CefString>& icon_urls) override;

  // CefLoadHandler:
  void OnLoadingStateChange(CefRefPtr<CefBrowser> browser,
                            bool isLoading,
                            bool canGoBack,
                            bool canGoForward) override;
  void OnLoadError(CefRefPtr<CefBrowser> browser,
                   CefRefPtr<CefFrame> frame,
                   ErrorCode errorCode,
                   const CefString& errorText,
                   const CefString& failedUrl) override;

 private:
  // Browser-id-keyed state shared across the (single) client instance.
  bool IsActive(CefRefPtr<CefBrowser> browser) const;

  IMPLEMENT_REFCOUNTING(ExperimentClient);
  DISALLOW_COPY_AND_ASSIGN(ExperimentClient);
};

// App-level callbacks. Also implements CefBrowserProcessHandler so we can
// create the browser once the context is initialized.
class ExperimentApp : public CefApp, public CefBrowserProcessHandler {
 public:
  ExperimentApp() = default;

  CefRefPtr<CefBrowserProcessHandler> GetBrowserProcessHandler() override {
    return this;
  }

  // CefApp:
  void OnBeforeCommandLineProcessing(
      const CefString& process_type,
      CefRefPtr<CefCommandLine> command_line) override;

  // CefBrowserProcessHandler:
  void OnContextInitialized() override;

 private:
  IMPLEMENT_REFCOUNTING(ExperimentApp);
  DISALLOW_COPY_AND_ASSIGN(ExperimentApp);
};
