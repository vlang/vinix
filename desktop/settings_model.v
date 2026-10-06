// Copyright (c) 2026 Alexander Medvednikov. All rights reserved.
// Use of this source code is governed by a GPL v2 license
// that can be found in the LICENSE file.

// SPDX-License-Identifier: GPL-2.0-or-later
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

// The language the desktop and its own applications speak. Each has a
// translations/<code>.tr file; translations.v looks text up in it.
enum DesktopLanguage {
	en
	ru
	es
	fr
	ja
}

const desktop_languages = [DesktopLanguage.en, .ru, .es, .fr, .ja]

// code names the language in the preferences file and its translation file.
fn (l DesktopLanguage) code() string {
	return match l {
		.en { 'en' }
		.ru { 'ru' }
		.es { 'es' }
		.fr { 'fr' }
		.ja { 'ja' }
	}
}

// native_name is what a language calls itself. A language picker lists it
// that way, so someone who cannot read the current language still finds
// their own.
fn (l DesktopLanguage) native_name() string {
	return match l {
		.en { 'English' }
		.ru { 'Русский' }
		.es { 'Español' }
		.fr { 'Français' }
		.ja { '日本語' }
	}
}

fn desktop_language_from_code(code string) ?DesktopLanguage {
	for language in desktop_languages {
		if language.code() == code {
			return language
		}
	}
	return none
}

struct Settings {
mut:
	button_side  ButtonSide
	taskbar_mode TaskbarMode
	theme        ThemeKind
	language     DesktopLanguage
	// Clock defaults preserve the desktop's existing taskbar presentation.
	clock_24_hour      bool = true
	clock_show_seconds bool = true
	clock_show_date    bool = true
	clock_show_weekday bool = true
	// Index into wallpaper_colors, used when no image is chosen.
	wallpaper_color int
	// Index into the wallpaper images, or -1 for the colour above.
	wallpaper_image int = -1
	// The input sources Ctrl-Space moves between, one KeyboardLayout.bit()
	// each, and the one typing uses now. The current one is always enabled.
	keyboard_layouts u32 = keyboard_layout_default_mask
	keyboard_layout  KeyboardLayout
}

// ── Keyboard ───────────────────────────────────────────────────────

// KeyboardLayout is an input source. keyboard_layout.v holds what each one
// types; this is what Settings, the preference file and the protocol name.
enum KeyboardLayout {
	us
	russian
	spanish
	french
	german
	portuguese
}

const keyboard_layouts = [KeyboardLayout.us, .russian, .spanish, .french, .german, .portuguese]
// English (US) alone: typing is exactly what the console delivers.
const keyboard_layout_default_mask = u32(1)
const keyboard_layout_all_mask = u32((1 << 6) - 1)

fn (l KeyboardLayout) title() string {
	return match l {
		.us { 'English (US)' }
		.russian { 'Russian' }
		.spanish { 'Spanish' }
		.french { 'French' }
		.german { 'German' }
		.portuguese { 'Portuguese' }
	}
}

// code names the layout in the preference file.
fn (l KeyboardLayout) code() string {
	return match l {
		.us { 'us' }
		.russian { 'ru' }
		.spanish { 'es' }
		.french { 'fr' }
		.german { 'de' }
		.portuguese { 'pt' }
	}
}

// badge is the short name the input-source panel shows.
fn (l KeyboardLayout) badge() string {
	return match l {
		.us { 'EN' }
		.russian { 'RU' }
		.spanish { 'ES' }
		.french { 'FR' }
		.german { 'DE' }
		.portuguese { 'PT' }
	}
}

fn (l KeyboardLayout) bit() u32 {
	return u32(1) << int(l)
}

fn keyboard_layout_from_code(code string) ?KeyboardLayout {
	for layout in keyboard_layouts {
		if layout.code() == code {
			return layout
		}
	}
	return none
}

// keyboard_layout_count says how many input sources a mask enables.
fn keyboard_layout_count(mask u32) int {
	mut count := 0
	for layout in keyboard_layouts {
		if mask & layout.bit() != 0 {
			count++
		}
	}
	return count
}

// keyboard_next_layout is the input source after `current` among the enabled
// ones, in the order Settings lists them.
fn keyboard_next_layout(mask u32, current KeyboardLayout) KeyboardLayout {
	for step in 1 .. keyboard_layouts.len + 1 {
		candidate := keyboard_layouts[(int(current) + step) % keyboard_layouts.len]
		if mask & candidate.bit() != 0 {
			return candidate
		}
	}
	return current
}

fn keyboard_first_layout(mask u32) KeyboardLayout {
	for layout in keyboard_layouts {
		if mask & layout.bit() != 0 {
			return layout
		}
	}
	return .us
}

fn keyboard_settings_valid(mask u32, current KeyboardLayout) bool {
	return mask != 0 && mask & ~keyboard_layout_all_mask == 0
		&& int(current) >= int(KeyboardLayout.us) && int(current) <= int(KeyboardLayout.portuguese)
		&& mask & current.bit() != 0
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
