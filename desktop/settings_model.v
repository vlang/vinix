// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
// Desktop preferences shared by Settings, the compositor and persistence.
// Keep this data model independent of the UI and POSIX backends.
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
	// Clock defaults preserve the desktop's existing taskbar presentation.
	clock_24_hour      bool = true
	clock_show_seconds bool = true
	// Index into wallpaper_colors, used when no image is chosen.
	wallpaper_color int
	// Index into the wallpaper images, or -1 for the colour above.
	wallpaper_image int = -1
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
