#pragma once

#include "include/cef_app.h"
#include "include/cef_client.h"
#include "include/cef_life_span_handler.h"

// Minimal browser client: owns the browser lifecycle callbacks.
class ExperimentClient : public CefClient, public CefLifeSpanHandler {
 public:
  ExperimentClient() = default;

  CefRefPtr<CefLifeSpanHandler> GetLifeSpanHandler() override { return this; }

  // Used by main.mm's window delegate to close the browser on window close.
  static CefRefPtr<CefBrowser> GetFirstBrowserForTesting();

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

 private:
  int browser_count_ = 0;

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
