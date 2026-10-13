// Copyright (c) 2026 Alexander Medvednikov. All rights reserved.
// Use of this source code is governed by a GPL v2 license
// that can be found in the LICENSE file.

// SPDX-License-Identifier: GPL-2.0-or-later
// What the desktop looks like and how its chrome behaves, and the four themes
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
// `aero` is Windows 7's caption group: three glass buttons hanging from the
// window's top edge, the close button wider than the other two and red while
// its window is focused. glass.v draws them. `luna` is Windows XP's three
// square buttons with white edges, the close button red; luna.v draws them.
enum ButtonLook {
	flat
	traffic
	aero
	luna
}

// Chrome says who paints a window's frame, the taskbar and the Start menu's
// shell: `flat` is the colours their elements declare, and the other two are
// renderers that know a look whole -- glass.v for Windows 7, luna.v for
// Windows XP. Under those a title bar is only there to be dragged and found.
enum Chrome {
	flat
	aero
	luna
}

// Theme is every colour and measurement that changes between looks. Anything
// the same in all of them stays a plain constant in theme.v.
struct Theme {
	name string
	// Windows
	window_body   u32
	window_edge   u32
	window_radius int
	shadow_alpha  u32
	// How far the drop shadow reaches, at most shadow_max_spread.
	shadow_spread int = 7
	chrome Chrome
	// Aero glass: the window frame, the taskbar and the Start menu show what
	// is behind them, blurred and tinted with Settings.glass_color. glass.v.
	glass bool
	// The frame around a window's body on its left, right and bottom. Zero is a
	// body that reaches the window's edges; Windows 7's glass is 8 pixels.
	frame_border int
	// The window's 16-pixel icon leads its title: how far in from the body's
	// left edge it starts, the gap between it and the text, and the colour a
	// builtin glyph is drawn in (an application's own artwork keeps its own).
	title_icon       bool
	title_icon_inset int
	title_icon_gap   int
	title_icon_color u32
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
	// panel like a dock. Some themes use large, icon-only task buttons instead
	// of labels, in the style of the Windows 7 taskbar.
	dock               bool
	taskbar_icon_only  bool
	dock_bg            u32
	dock_radius        int
	dock_padding       int
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
	// Keep the Catalina window chrome, but give its desktop a practical
	// Windows-7-style taskbar: it spans the bottom edge and uses large icons.
	dock: false
	taskbar_icon_only: true
	dock_bg: 0x4d6f91
	dock_radius: 12
	dock_padding: 8
	taskbar_bg: 0x4d6f91
	taskbar_edge: 0xa9c0d7
	taskbar_text: 0xe8f1fb
	taskbar_text_active: 0xffffff
	taskbar_muted: 0xd1deeb
	taskbar_item_bg: 0x5d84ab
	taskbar_item_hover: 0x7199c0
	taskbar_item_active: 0x88add0
	accent: 0x3478d4
	accent_dim: 0xc9d6ea
	shortcut_label: 0xffffff
	shortcut_hover: 0xffffff
	shortcut_panel: 0x000000
}

// Windows 7 with Aero. The frame, the taskbar and the Start menu are glass
// (glass.v), so the title and taskbar colours below are only what marks a
// state for that renderer, or what a surface without glass falls back to.
// The measurements are Windows 7's at 96 DPI: an 8-pixel frame around the
// body and a 22-pixel caption above it, 30 pixels from the window's top edge.
const theme_windows7 = Theme{
	name: 'Windows 7'
	window_body: 0xf0f0f0
	window_edge: 0x6f7b8c
	window_radius: 7
	shadow_alpha: 64
	shadow_spread: 12
	chrome: .aero
	glass: true
	frame_border: 8
	title_icon: true
	title_icon_inset: 8
	title_icon_gap: 6
	title_icon_color: 0x1e3a5f
	title_height: 30
	title_active_bg: 0xb9d1ea
	title_active_bg2: 0xb9d1ea
	title_inactive_bg: 0xd7e4f2
	title_inactive_bg2: 0xd7e4f2
	title_highlight: 0
	title_inactive_highlight: 0
	title_divider: 0x8c98a8
	title_inactive_divider: 0xa9b3c0
	// Windows 7 keeps the title black on an unfocused window; the glass and the
	// caption buttons are what fade.
	title_text_active: 0x000000
	title_text_inactive: 0x000000
	title_centered: false
	title_bold: false
	title_size: 12
	button_look: .aero
	button_size: aero_caption_maximize_width
	button_gap: 0
	button_inset: aero_caption_inset
	button_hover: 0x3a8ee6
	button_close_hover: 0xe0432d
	button_face: 0xdfe9f5
	button_edge: 0x535a66
	glyph_color: 0xffffff
	glyph_on_close: 0xffffff
	dock: false
	taskbar_icon_only: true
	dock_bg: 0x3d5a80
	dock_radius: 12
	dock_padding: 8
	taskbar_bg: 0x3d5a80
	taskbar_edge: 0x1c2a3d
	taskbar_text: 0xffffff
	taskbar_text_active: 0xffffff
	taskbar_muted: 0xe1eaf4
	taskbar_item_bg: 0x4f6f97
	taskbar_item_hover: 0x7396c0
	taskbar_item_active: 0x8fb0d8
	accent: 0x3399ff
	accent_dim: 0x2a66ad
	shortcut_label: 0xffffff
	shortcut_hover: 0xffffff
	shortcut_panel: 0x000000
}

// Windows XP's Luna in its blue. A window has the blue title bar with round
// upper corners, white bold text and three square buttons, and a 4-pixel blue
// frame; the taskbar is the blue bar with the green Start button. luna.v
// paints all of it, so most colours below only mark a state for it. The
// measurements are Windows XP's at 96 DPI: 30 pixels from a window's top
// edge to its body, 21-pixel caption buttons two pixels apart.
const theme_windows_xp = Theme{
	name: 'Windows XP'
	window_body: 0xece9d8
	window_edge: 0x0831d9
	// Only the upper corners are round, so luna.v cuts them itself.
	window_radius: 0
	shadow_alpha: 0
	chrome: .luna
	frame_border: 4
	title_icon: true
	title_icon_inset: 2
	title_icon_gap: 4
	title_icon_color: 0xffffff
	title_height: 30
	title_active_bg: 0x0054e3
	title_active_bg2: 0x0054e3
	title_inactive_bg: 0x7a96df
	title_inactive_bg2: 0x7a96df
	title_highlight: 0
	title_inactive_highlight: 0
	title_divider: 0x003092
	title_inactive_divider: 0xabbae3
	title_text_active: 0xffffff
	title_text_inactive: 0xd8e4f8
	title_centered: false
	title_bold: true
	title_size: 13
	button_look: .luna
	button_size: luna_caption_size
	button_gap: luna_caption_gap
	button_inset: luna_caption_inset
	button_hover: 0x3c81f3
	button_close_hover: 0xe0432b
	button_face: 0x2263d5
	button_edge: 0xffffff
	glyph_color: 0xffffff
	glyph_on_close: 0xffffff
	dock: false
	dock_bg: 0x245edb
	dock_radius: 12
	dock_padding: 8
	taskbar_bg: 0x245edb
	taskbar_edge: 0x1f2f86
	taskbar_text: 0xffffff
	taskbar_text_active: 0xffffff
	taskbar_muted: 0xd6e4fb
	taskbar_item_bg: 0x3c81f3
	taskbar_item_hover: 0x53a3ff
	taskbar_item_active: 0x1e52b7
	accent: 0x316ac5
	accent_dim: 0x3c873c
	shortcut_label: 0xffffff
	shortcut_hover: 0xffffff
	shortcut_panel: 0x000000
}

fn (d &Desktop) theme() Theme {
	return match d.settings.theme {
		.default_ { theme_default }
		.macos { theme_macos }
		.windows7 { theme_windows7 }
		.windows_xp { theme_windows_xp }
	}
}

// window_border is the frame around this window's body on its left, right and
// bottom. A maximized window has none: Windows pushes that part of the frame
// off the screen.
fn (d &Desktop) window_border(window &Window) int {
	return if window.maximized { 0 } else { d.theme().frame_border }
}
