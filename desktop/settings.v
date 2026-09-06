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
	classic
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

// TitleFill says how a title bar is painted. `pinstripe` is the horizontal
// hairline pattern Mac OS 8 and 9 drew across theirs, which is most of what
// makes that look recognisable.
enum TitleFill {
	flat
	pinstripe
}

// ButtonLook says how the title bar buttons are drawn. `flat` is a glyph that
// only shows a background under the pointer; `classic` is a raised bevelled
// square that is always visible, which is what those systems had.
enum ButtonLook {
	flat
	classic
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
	title_fill          TitleFill
	title_pinstripe     u32
	title_centered      bool
	title_bold          bool
	// Title bar buttons
	button_look        ButtonLook
	button_hover       u32
	button_close_hover u32
	button_face        u32
	button_edge        u32
	glyph_color        u32
	glyph_on_close     u32
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
	clock_time          u32
	clock_date          u32
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
	title_divider: 0xe4e8ee
	title_text_active: 0x18202f
	title_text_inactive: 0x99a2b1
	title_fill: .flat
	title_pinstripe: 0xffffff
	title_centered: false
	title_bold: true
	button_look: .flat
	button_hover: 0xe7eaf0
	button_close_hover: 0xe5484d
	button_face: 0xe7eaf0
	button_edge: 0xb9c2d0
	glyph_color: 0x3b465a
	glyph_on_close: 0xffffff
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
	clock_time: 0xffffff
	clock_date: 0x8fa0bd
	shortcut_label: 0xecf2fb
	shortcut_hover: 0xffffff
	shortcut_panel: 0x141d33
}

// Mac OS 8/9's Platinum: square grey windows with a hairline border, a
// pinstriped title bar with the title centred over it, and bevelled buttons
// that are always visible rather than appearing under the pointer.
const theme_classic = Theme{
	name: 'Classic'
	window_body: 0xdddddd
	window_edge: 0x000000
	window_radius: 0
	shadow_alpha: 90
	title_height: 22
	title_active_bg: 0xcccccc
	title_inactive_bg: 0xdddddd
	title_divider: 0x000000
	title_text_active: 0x000000
	title_text_inactive: 0x888888
	title_fill: .pinstripe
	title_pinstripe: 0xffffff
	title_centered: true
	title_bold: true
	button_look: .classic
	button_hover: 0xbbbbbb
	button_close_hover: 0xbbbbbb
	button_face: 0xcccccc
	button_edge: 0x000000
	glyph_color: 0x000000
	glyph_on_close: 0x000000
	taskbar_bg: 0xbbbbbb
	taskbar_edge: 0x000000
	taskbar_text: 0x000000
	taskbar_text_active: 0x000000
	taskbar_muted: 0x777777
	taskbar_item_bg: 0xcccccc
	taskbar_item_hover: 0xdddddd
	taskbar_item_active: 0xaaaaaa
	accent: 0x9999cc
	accent_dim: 0xcccccc
	clock_time: 0x000000
	clock_date: 0x444444
	shortcut_label: 0x000000
	shortcut_hover: 0x000000
	shortcut_panel: 0xcccccc
}

const themes = [theme_default, theme_classic]

fn (d &Desktop) theme() Theme {
	return match d.settings.theme {
		.default_ { theme_default }
		.classic { theme_classic }
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
	WallpaperColor{'Classic teal', 0x5f8f8f, 0x5f8f8f},
]
