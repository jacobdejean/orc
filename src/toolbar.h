#pragma once

#include <string>

// Bridge between the CEF client (experiment_app.mm) and the native toolbar
// (main.mm). CEF calls these on the UI thread, which is the same thread as
// the AppKit run loop, so direct NSView updates are safe.

// Height of the toolbar strip pinned to the top of the window's contentView.
// The browser view is laid out below it.
constexpr int kToolbarHeight = 40;

// Implemented in main.mm.
void ToolbarSetAddressText(const std::string& url);
void ToolbarSetLoadingState(bool is_loading, bool can_go_back,
                            bool can_go_forward);
