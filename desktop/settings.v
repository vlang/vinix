// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
// What the desktop looks like and how its chrome behaves, and the two themes
// it can wear.
//
// The preference model lives in settings_model.v. The window manager
// reads `Desktop.settings` for behaviour and `Desktop.theme()` for colour, so
// a preference takes effect on the next frame without anything being rebuilt
// or reopened — the tree is composed from scratch each time anyway.
module main

// ── Themes ─────────────────────────────────────────────────────────

// ButtonLook says how the title bar buttons are drawn. `flat` is a glyph that
// only shows a background under the pointer. `traffic` is the three coloured
// discs macOS puts at the leading edge, which are grey until the window is
// focused and show their glyphs only while the pointer is over the set.
enum ButtonLook {
	flat
	traffic
}

// Theme is every colour and measurement that changes between looks. Anything
// the same in both stays a plain constant in theme.v.
struct Theme {
	name string
	// Windows
	window_body   u32
	window_edge   u32
	window_radius int
	shadow_alpha  u32
	// Title bar
	title_height             int
	title_active_bg          u32
	title_inactive_bg        u32
	title_highlight          u32
	title_inactive_highlight u32
	title_divider            u32
	title_inactive_divider   u32
	title_text_active        u32
	title_text_inactive      u32
	title_centered           bool
	title_bold               bool
	title_size               int
	// A second colour for the title bar, blended down its height. A theme that
	// wants a flat bar names the same colour twice.
	title_active_bg2   u32
	title_inactive_bg2 u32
	// Title bar buttons
	button_look        ButtonLook
	button_size        int
	button_gap         int
	button_inset       int
	button_hover       u32
	button_close_hover u32
	button_face        u32
	button_edge        u32
	glyph_color        u32
	glyph_on_close     u32
	// The three discs, in close/minimise/zoom order, and the grey they all go
	// when the window is not the focused one.
	traffic_close          u32
	traffic_minimize       u32
	traffic_zoom           u32
	traffic_idle           u32
	traffic_close_edge     u32
	traffic_minimize_edge  u32
	traffic_zoom_edge      u32
	traffic_idle_edge      u32
	traffic_close_glyph    u32
	traffic_minimize_glyph u32
	traffic_zoom_glyph     u32
	// The bar along the bottom: full width like a taskbar, or a centred rounded
	// panel like a dock.
	dock         bool
	dock_bg      u32
	dock_radius  int
	dock_padding int
	// Taskbar
	taskbar_bg          u32
	taskbar_edge        u32
	taskbar_text        u32
	taskbar_text_active u32
	taskbar_muted       u32
	taskbar_item_bg     u32
	taskbar_item_hover  u32
	taskbar_item_active u32
	accent              u32
	accent_dim          u32
	// Wallpaper shortcuts
	shortcut_label u32
	shortcut_hover u32
	shortcut_panel u32
}

// The desktop's own look: rounded, shadowed, flat-coloured.
const theme_default = Theme{
	name: 'Default'
	window_body: 0xfbfcfe
	window_edge: 0xb9c2d0
	window_radius: 9
	shadow_alpha: 150
	title_height: 34
	title_active_bg: 0xffffff
	title_inactive_bg: 0xf1f3f6
	title_highlight: 0
	title_inactive_highlight: 0
	title_active_bg2: 0xffffff
	title_inactive_bg2: 0xf1f3f6
	title_divider: 0xe4e8ee
	title_inactive_divider: 0xe4e8ee
	title_text_active: 0x18202f
	title_text_inactive: 0x99a2b1
	title_centered: false
	title_bold: true
	title_size: 13
	button_look: .flat
	button_size: 22
	button_gap: 4
	button_inset: 8
	button_hover: 0xe7eaf0
	button_close_hover: 0xe5484d
	button_face: 0xe7eaf0
	button_edge: 0xb9c2d0
	glyph_color: 0x3b465a
	glyph_on_close: 0xffffff
	traffic_close: 0xff5f57
	traffic_minimize: 0xfebc2e
	traffic_zoom: 0x28c840
	traffic_idle: 0xd6d6d6
	traffic_close_edge: 0xb9c2d0
	traffic_minimize_edge: 0xb9c2d0
	traffic_zoom_edge: 0xb9c2d0
	traffic_idle_edge: 0xb9c2d0
	traffic_close_glyph: 0x3b465a
	traffic_minimize_glyph: 0x3b465a
	traffic_zoom_glyph: 0x3b465a
	dock: false
	dock_bg: 0xd8dce4
	dock_radius: 12
	dock_padding: 8
	taskbar_bg: 0x101726
	taskbar_edge: 0x28344e
	taskbar_text: 0xc3cddf
	taskbar_text_active: 0xffffff
	taskbar_muted: 0x76839a
	taskbar_item_bg: 0x1b2436
	taskbar_item_hover: 0x27334b
	taskbar_item_active: 0x2c3d5e
	accent: 0x5b9cf8
	accent_dim: 0x27436e
	shortcut_label: 0xecf2fb
	shortcut_hover: 0xffffff
	shortcut_panel: 0x141d33
}

// macOS Catalina 10.15.7: the measurements and colours below come from a
// native 1x AppKit window in Apple's 19H2 recovery system. The one-pixel top
// highlight is separate from the 20-step title gradient, just as it is in the
// reference window.
const theme_macos = Theme{
	name: 'macOS'
	window_body: 0xececec
	window_edge: 0x9a9a9a
	window_radius: 6
	shadow_alpha: 120
	title_height: 22
	title_active_bg: 0xe4e4e4
	title_active_bg2: 0xd1d1d1
	title_inactive_bg: 0xf6f6f6
	title_inactive_bg2: 0xf6f6f6
	title_highlight: 0xf3f3f3
	title_inactive_highlight: 0xfbfbfb
	title_divider: 0xababab
	title_inactive_divider: 0xd1d1d1
	title_text_active: 0x333333
	title_text_inactive: 0xa8a8a8
	title_centered: true
	title_bold: true
	title_size: 13
	button_look: .traffic
	button_size: 12
	button_gap: 8
	button_inset: 8
	button_hover: 0xdcdcdc
	button_close_hover: 0xdcdcdc
	button_face: 0xdcdcdc
	button_edge: 0x9a9a9a
	glyph_color: 0x4d0000
	glyph_on_close: 0x4d0000
	traffic_close: 0xff5f57
	traffic_minimize: 0xffbd2e
	traffic_zoom: 0x28c940
	traffic_idle: 0xdcdcdc
	traffic_close_edge: 0xe0463e
	traffic_minimize_edge: 0xdea123
	traffic_zoom_edge: 0x1aab29
	traffic_idle_edge: 0xd1d1d1
	traffic_close_glyph: 0x4d0000
	traffic_minimize_glyph: 0x995700
	traffic_zoom_glyph: 0x006500
	dock: true
	dock_bg: 0xe8e8ea
	dock_radius: 12
	dock_padding: 8
	taskbar_bg: 0xe8e8ea
	taskbar_edge: 0xc4c4c8
	taskbar_text: 0x2c2c2e
	taskbar_text_active: 0x000000
	taskbar_muted: 0x8e8e93
	taskbar_item_bg: 0xdcdce0
	taskbar_item_hover: 0xcfcfd4
	taskbar_item_active: 0xc0c0c6
	accent: 0x3478d4
	accent_dim: 0xc9d6ea
	shortcut_label: 0xffffff
	shortcut_hover: 0xffffff
	shortcut_panel: 0x000000
}

fn (d &Desktop) theme() Theme {
	return match d.settings.theme {
		.default_ { theme_default }
		.macos { theme_macos }
	}
}
