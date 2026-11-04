#pragma once

#import <Cocoa/Cocoa.h>

// Design tokens for the experiment's native chrome.
//
// This is the style system: every color, radius, spacing value, and font the
// chrome uses is defined ONCE here, and components (sidebar rows, buttons,
// fields) read from these instead of hardcoding literals. To restyle the
// whole app you edit this file. As the UI grows, group tokens per component
// (e.g. a TabRow struct) rather than adding more free functions.
//
// Naming follows "what it means", not "what it looks like"
// (kTextPrimary, not kWhite80) so palette swaps don't create lying names.

namespace theme {

// --- Palette ---------------------------------------------------------------
// Alphas are over the sidebar's vibrancy material (NSVisualEffectMaterial-
// Sidebar), so they're relative to whatever wallpaper/tint shows through.

inline NSColor* RowBackgroundHover() {
  return [NSColor colorWithWhite:1.0 alpha:0.06];
}
inline NSColor* RowBackgroundActive() {
  return [NSColor colorWithWhite:1.0 alpha:0.12];
}
inline NSColor* TextPrimary() {
  return [NSColor labelColor];
}
inline NSColor* TextSecondary() {
  return [NSColor secondaryLabelColor];
}

// --- Geometry ----------------------------------------------------------------

inline CGFloat CornerRadiusSmall() { return 4; }   // buttons, chips
inline CGFloat CornerRadiusRow() { return 6; }     // tab rows, URL field bg
inline CGFloat SpacingXS() { return 4; }
inline CGFloat SpacingS() { return 8; }
inline CGFloat SpacingM() { return 12; }
inline CGFloat SpacingL() { return 16; }

// --- Typography ----------------------------------------------------------------

inline NSFont* RowTitleFont() {
  return [NSFont systemFontOfSize:13 weight:NSFontWeightRegular];
}

}  // namespace theme
