// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
// What the desktop looks like and how its chrome behaves, and the two themes
// it can wear.
//
// Everything the Settings application changes lives here. The window manager
// reads `Desktop.settings` for behaviour and `Desktop.theme()` for colour, so
// a preference takes effect on the next frame without anything being rebuilt
// or reopened — the tree is composed from scratch each time anyway.
module main

// Which end of the title bar the close, zoom and minimise buttons sit at.
// Right is what Windows does; left is what macOS does.
enum ButtonSide {
	right
	left
}

// How the taskbar lists what is open. `standard` gives every window its own
// entry, the way Windows XP did. `combined` gives each application one entry
// however many windows it has, the way Windows 7 did.
enum TaskbarMode {
	standard
	combined
}

enum ThemeKind {
	default_
	macos
}

struct Settings {
mut:
	button_side  ButtonSide
	taskbar_mode TaskbarMode
	theme        ThemeKind
	// Index into wallpaper_colors, used when no image is chosen.
	wallpaper_color int
	// Index into the wallpaper images, or -1 for the colour above.
	wallpaper_image int = -1
}

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
	title_height        int
	title_active_bg     u32
	title_inactive_bg   u32
	title_divider       u32
	title_text_active   u32
	title_text_inactive u32
	title_centered      bool
	title_bold          bool
	title_size          int
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
	traffic_close    u32
	traffic_minimize u32
	traffic_zoom     u32
	traffic_idle     u32
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
	title_active_bg2: 0xffffff
	title_inactive_bg2: 0xf1f3f6
	title_divider: 0xe4e8ee
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

// macOS as it looked from Yosemite through Mojave: light grey window chrome
// with the title centred over it, three coloured discs at the leading edge,
// and a dock rather than a taskbar.
const theme_macos = Theme{
	name: 'macOS'
	window_body: 0xffffff
	window_edge: 0x9a9a9a
	window_radius: 6
	shadow_alpha: 120
	title_height: 24
	title_active_bg: 0xeaeaea
	title_active_bg2: 0xd8d8d8
	title_inactive_bg: 0xf6f6f6
	title_inactive_bg2: 0xf0f0f0
	title_divider: 0xb4b4b4
	title_text_active: 0x3a3a3c
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
	traffic_minimize: 0xfebc2e
	traffic_zoom: 0x28c840
	traffic_idle: 0xd6d6d6
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

// ── Wallpaper ──────────────────────────────────────────────────────

// WallpaperColor is a flat backdrop. Each is a pair, because the desktop
// paints a vertical gradient; a colour that wants to be flat names itself
// twice.
struct WallpaperColor {
	name   string
	top    u32
	bottom u32
}

const wallpaper_colors = [
	WallpaperColor{'Midnight', 0x141d33, 0x3c5a86},
	WallpaperColor{'Slate', 0x2b3038, 0x4d545e},
	WallpaperColor{'Forest', 0x11301f, 0x2f6b46},
	WallpaperColor{'Plum', 0x2a1533, 0x5d3a70},
	WallpaperColor{'Ember', 0x33190f, 0x8a4426},
	WallpaperColor{'Graphite', 0x6e6e73, 0x6e6e73},
]
