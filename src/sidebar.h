#pragma once

#include <string>

// Bridge between the CEF client (experiment_app.mm) and the native chrome.
// CEF calls these on the UI thread, which is the same thread as the AppKit
// run loop, so direct NSView updates are safe.

// Width of the sidebar pinned to the left edge of the window's contentView.
constexpr int kSidebarWidth = 180;

// --- Lifecycle (implemented in sidebar.mm) -----------------------------------
@class NSView;
void SidebarCreate(NSView* contentView, CGFloat height);
void SidebarToggleHidden();

// --- Tab list (implemented in sidebar.mm) ------------------------------------
void SidebarTabAdded(int browser_id);
void SidebarTabRemoved(int browser_id);
void SidebarSetActiveTab(int browser_id);
void SidebarTabSetTitle(int browser_id, const std::string& title);
void SidebarTabSetFaviconURL(int browser_id, const std::string& icon_url);

// --- Active-tab state (implemented in sidebar.mm) ----------------------------
void SidebarSetAddressText(const std::string& url);
void SidebarSetLoadingState(bool is_loading, bool can_go_back,
                            bool can_go_forward);
bool SidebarIsHidden();
void SidebarFocusAddressField();

// --- Start placeholder (implemented in main.mm) ------------------------------
// Shown in the content area when no tabs are open.
void StartViewSetVisible(bool visible);
