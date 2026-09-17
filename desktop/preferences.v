// SPDX-License-Identifier: GPL-2.0-or-later
// One versioned record for every desktop preference. No device readback,
// pending request, or application-local state belongs in this file.
module main

const desktop_preferences_name = '.vinix-desktop-settings'
const desktop_preferences_max_bytes = 4096
const desktop_legacy_scale_name = '.vinix-desktop-scale'

struct DesktopPreferences {
mut:
	settings Settings
	// Zero keeps geometry-based selection. Saving a theme or wallpaper must
	// not turn an automatic scale into a permanent display override.
	scale int
}

fn (p DesktopPreferences) configure_scale(width int, height int) int {
	fallback := desktop_configure_scale(width, height)
	if !desktop_scale_valid(p.scale) {
		return fallback
	}
	desktop_request_scale(p.scale)
	desktop_commit_scale(p.scale)
	return p.scale
}

fn desktop_preferences_valid(p DesktopPreferences) bool {
	return (p.scale == 0 || desktop_scale_valid(p.scale))
		&& int(p.settings.button_side) >= int(ButtonSide.right)
		&& int(p.settings.button_side) <= int(ButtonSide.left)
		&& int(p.settings.taskbar_mode) >= int(TaskbarMode.standard)
		&& int(p.settings.taskbar_mode) <= int(TaskbarMode.combined)
		&& int(p.settings.theme) >= int(ThemeKind.default_)
		&& int(p.settings.theme) <= int(ThemeKind.macos)
		&& p.settings.wallpaper_color >= 0
		&& p.settings.wallpaper_color < wallpaper_colors.len
		&& p.settings.wallpaper_image >= -1
}

fn desktop_encode_preferences(p DesktopPreferences) ?string {
	if !desktop_preferences_valid(p) {
		return none
	}
	scale := match p.scale {
		0 { 'auto' }
		desktop_scale_100 { '1' }
		else { '2' }
	}
	side := if p.settings.button_side == .left { 'left' } else { 'right' }
	taskbar := if p.settings.taskbar_mode == .combined { 'combined' } else { 'standard' }
	theme := if p.settings.theme == .macos { 'macos' } else { 'default' }
	clock_24_hour := if p.settings.clock_24_hour { 'true' } else { 'false' }
	clock_show_seconds := if p.settings.clock_show_seconds { 'true' } else { 'false' }
	clock_show_date := if p.settings.clock_show_date { 'true' } else { 'false' }
	clock_show_weekday := if p.settings.clock_show_weekday { 'true' } else { 'false' }
	return 'version=1\nscale=${scale}\nbutton_side=${side}\ntaskbar_mode=${taskbar}\ntheme=${theme}\nclock_24_hour=${clock_24_hour}\nclock_show_seconds=${clock_show_seconds}\nclock_show_date=${clock_show_date}\nclock_show_weekday=${clock_show_weekday}\nwallpaper_color=${p.settings.wallpaper_color}\nwallpaper_image=${p.settings.wallpaper_image}\n'
}

// Unlike string.int(), this cannot accept a numeric prefix or wrap on overflow.
fn desktop_preference_index(text string) ?int {
	if text == '-1' {
		return -1
	}
	if text.len == 0 || text.len > 10 {
		return none
	}
	mut value := 0
	for byte in text {
		if byte < `0` || byte > `9` {
			return none
		}
		digit := int(byte - `0`)
		if value > (2147483647 - digit) / 10 {
			return none
		}
		value = value * 10 + digit
	}
	return value
}

// Parse borrowed slices, not a tree of allocated strings: the desktop uses
// -manualfree. Missing keys keep defaults; unknown keys allow schema extension.
// Reject malformed or duplicate known fields as a whole, never partially apply
// a damaged snapshot. A version is mandatory, including for an otherwise empty
// record. File loading is separately bounded and rejects non-regular files.
fn desktop_parse_preferences(record string) ?DesktopPreferences {
	if record.len == 0 || record.len > desktop_preferences_max_bytes
		|| record.index_u8(0) >= 0 {
		return none
	}
	mut p := DesktopPreferences{}
	mut seen := u32(0)
	mut start := 0
	for start < record.len {
		mut end := start
		for end < record.len && record[end] != `\n` {
			end++
		}
		line := record[start..end].trim_space()
		start = end + 1
		if line.len == 0 || line.starts_with('#') {
			continue
		}
		equals := line.index_u8(`=`)
		if equals <= 0 {
			return none
		}
		key := line[..equals].trim_space()
		value := line[equals + 1..].trim_space()
		bit := match key {
			'version' { u32(1) }
			'scale' { u32(2) }
			'button_side' { u32(4) }
		
'taskbar_mode' { u32(8) }
		
'theme' { u32(16) }
			'wallpaper_color' { u32(32) }
			'wallpaper_image' { u32(64) }
			'clock_24_hour' { u32(128) }
			'clock_show_seconds' { u32(256) }
			'clock_show_date' { u32(512) }
			'clock_show_weekday' { u32(1024) }
			else { u32(0) }
		}
		if seen & bit != 0 {
			return none
		}
		seen |= bit
		match key {
			'version' {
				if value != '1' { return none }
			}
			'scale' {
				p.scale = match value {
					'auto' { 0 }
					'1' { desktop_scale_100 }
					'2' { desktop_scale_200 }
					else { return none }
				}
			}
			'button_side' {
				p.settings.button_side = match value {
					'right' { ButtonSide.right }
					'left' { ButtonSide.left }
					else { return none }
				}
			}
			'taskbar_mode' {
				p.settings.taskbar_mode = match value {
					'standard' { TaskbarMode.standard }
					'combined' { TaskbarMode.combined }
					else { return none }
				}
			}
		
'theme' {
				p.settings.theme = match value {
					'default' { ThemeKind.default_ }
					'macos' { ThemeKind.macos }
					else { return none }
				}
			}
			'clock_24_hour' {
				p.settings.clock_24_hour = match value {
					'true' { true }
					'false' { false }
					else { return none }
				}
			}
			'clock_show_seconds' {
				p.settings.clock_show_seconds = match value {
					'true' { true }
					'false' { false }
					else { return none }
				}
			}
			'clock_show_date' {
				p.settings.clock_show_date = match value {
					'true' { true }
					'false' { false }
					else { return none }
				}
			}
			'clock_show_weekday' {
				p.settings.clock_show_weekday = match value {
					'true' { true }
					'false' { false }
					else { return none }
				}
			}
			'wallpaper_color' { p.settings.wallpaper_color = desktop_preference_index(value)? }
			'wallpaper_image' { p.settings.wallpaper_image = desktop_preference_index(value)? }
			else {}
		}
	}
	if seen & u32(1) == 0 || !desktop_preferences_valid(p) {
		return none
	}
	return p
}
