// The Settings application: categories down the left, the chosen category's
// settings on the right.
//
// It is a hosted application like any other, but unlike the file browser it
// changes the desktop rather than reading it, so it holds a pointer back to
// the Desktop and writes preferences straight into it. The window manager
// composes the whole screen from those preferences on the next frame, which is
// why a choice made here shows up immediately and everywhere without anything
// being told to refresh.
module main

import ui2

enum SettingsCategory {
	appearance
	theme
	wallpaper
	wifi
	display
	battery
}

const settings_categories = [SettingsCategory.appearance, .theme, .wallpaper, .wifi,
	.display, .battery]

fn (c SettingsCategory) title() string {
	return match c {
		.appearance { 'Appearance' }
		.theme { 'Theme' }
		.wallpaper { 'Wallpaper' }
		.wifi { 'Wi-Fi' }
		.display { 'Display' }
		.battery { 'Battery' }
	}
}

const settings_action_category = 'settings.category.'
const settings_action_side = 'settings.side.'
const settings_action_taskbar = 'settings.taskbar.'
const settings_action_theme = 'settings.theme.'
const settings_action_color = 'settings.color.'
const settings_action_image = 'settings.image.'

const settings_sidebar_width = 132
const settings_padding = 16
const settings_row_gap = 8

struct SettingsApp {
mut:
	// The desktop this is changing. A hosted application usually knows nothing
	// about the desktop; this one is the exception, and is the reason
	// HostedApp's build takes only a size — everything else it needs, it holds.
	desktop  &Desktop = unsafe { nil }
	category SettingsCategory = .appearance
	images   []WallpaperImage
	// Display, Battery and Wi-Fi read devices rather than the desktop's own
	// preferences, so they carry the last readback and the labels made from
	// it. The reads are injectable so host tests can drive them.
	battery_read  fn (bool) int         = read_battery
	state         BacklightState
	read_result   BacklightResult       = .unavailable
	write_result  BacklightResult
	last_poll_ms  u64
	initialized   bool
	read_state    fn (mut BacklightState) BacklightResult = read_backlight
	write_percent fn (int) BacklightResult = set_backlight_percent
	wifi_state         WifiState
	wifi_read_result   WifiResult = .unavailable
	wifi_action_result WifiResult
	wifi_last_poll_ms  u64
	wifi_initialized   bool
	wifi_read          fn (mut WifiState) WifiResult = read_wifi
	wifi_radio         fn (bool) WifiResult = set_wifi_radio
	wifi_scan          fn () WifiResult = scan_wifi
	wifi_names         [32]string
	wifi_details       [32]string
	wifi_offset        int
	// Owned, cached labels. Replaced only when a readback changes, never per
	// frame: the framebuffer renderer frees child arrays, not strings.
	level_text     string
	requested_text string
	actual_text    string
	range_text     string
}

fn (mut d Desktop) open_settings() !HostedApp {
	return &SettingsApp{
		desktop: d
		images: list_wallpapers()
	}
}

fn (mut a SettingsApp) build(size ui2.Rect) !ui2.Element {
	width := int(size.width)
	height := int(size.height)

	mut children := []ui2.Element{}

	// The sidebar, and a hairline between it and the pane.
	children << ui2.view('', ui2.rect(0, 0, f64(settings_sidebar_width), f64(height)),
		ui2.BoxStyle{
		bg: settings_sidebar_bg
	}, a.category_rows())
	children << ui2.view('', ui2.rect(f64(settings_sidebar_width), 0, 1, f64(height)),
		ui2.BoxStyle{
		bg: body_rule
	}, [])

	pane_x := settings_sidebar_width + 1
	pane_width := width - pane_x
	// Display polls the panel no more often than the desktop redraws for its
	// clock, and picks up a change another Settings window made.
	if a.category == .display {
		now := desktop_monotonic_ms()
		if !a.initialized || (now != ~u64(0) && (now < a.last_poll_ms
			|| now - a.last_poll_ms >= 1000)) {
			a.refresh()
		}
	}
	if a.category == .wifi {
		now := desktop_monotonic_ms()
		if !a.wifi_initialized || (now != ~u64(0) && (now < a.wifi_last_poll_ms
			|| now - a.wifi_last_poll_ms >= 1000)) {
			a.refresh_wifi()
		}
	}

	children << ui2.view('', ui2.rect(f64(pane_x), 0, f64(pane_width), f64(height)), ui2.BoxStyle{
		bg: app_surface
	}, a.pane(pane_width, height))

	// The screen's own background never shows; the two panes cover it. It is
	// the application surface so that a window resized oddly still looks whole.
	return ui2.screen(app_surface, children)
}

// Display and Battery report a device and change nothing here, so they draw
// without a desktop behind them. The other three are the desktop's own
// preferences and have nothing to show without one.
fn (a &SettingsApp) pane(width int, height int) []ui2.Element {
	match a.category {
		.wifi { return a.wifi_pane(width, height) }
		.display { return a.display_pane(width) }
		.battery { return a.battery_pane(width) }
		else {}
	}
	if a.desktop == unsafe { nil } {
		return []ui2.Element{}
	}
	return match a.category {
		.appearance { a.appearance_pane(width) }
		.theme { a.theme_pane(width) }
		.wallpaper { a.wallpaper_pane(width) }
		else { []ui2.Element{} }
	}
}

fn (a &SettingsApp) category_rows() []ui2.Element {
	mut rows := []ui2.Element{cap: settings_categories.len}
	for index, category in settings_categories {
		selected := category == a.category
		y := settings_padding + index * 32
		rows << ui2.clickable_view('${settings_action_category}${index}', ui2.rect(6, f64(y),
			f64(settings_sidebar_width - 12), 28), ui2.BoxStyle{
			bg: settings_category_selected
			radius: 6
			transparent: !selected
		}, [
			ui2.label('', category.title(), ui2.rect(12, 0, f64(settings_sidebar_width - 24),
				28), ui2.TextStyle{
				color: if selected { body_heading } else { body_text }
				size: 13
				bold: selected
			}),
		])
	}
	return rows
}

// heading_row and option_row give every pane the same shape: a heading, a
// sentence saying what the choice means, then the choices themselves.
fn settings_heading(text string, y int, width int) ui2.Element {
	return ui2.label('', text, ui2.rect(f64(settings_padding), f64(y), f64(width - 2 * settings_padding),
		20), ui2.TextStyle{
		color: body_heading
		size: 13
		bold: true
	})
}

fn settings_note(text string, y int, width int) ui2.Element {
	return ui2.label('', text, ui2.rect(f64(settings_padding), f64(y), f64(width - 2 * settings_padding),
		16), ui2.TextStyle{
		color: body_muted
		size: 11
	})
}

// choice draws one option as a radio-style pill: filled when it is the current
// setting, outlined when it is not.
fn settings_choice(id string, label string, x int, y int, width int, selected bool) ui2.Element {
	return ui2.button(id, label, ui2.rect(f64(x), f64(y), f64(width), 28), ui2.BoxStyle{
		bg: if selected { app_accent } else { settings_choice_bg }
		radius: 6
	}, ui2.TextStyle{
		color: if selected { app_on_accent } else { body_text }
		size: 12
		align: .center
	})
}

fn (a &SettingsApp) appearance_pane(width int) []ui2.Element {
	settings := a.desktop.settings
	inner := width - 2 * settings_padding
	half := (inner - settings_row_gap) / 2

	mut out := []ui2.Element{}
	mut y := settings_padding

	out << settings_heading('Window buttons', y, width)
	y += 22
	out << settings_note('Which end of the title bar close and zoom sit at.', y, width)
	y += 22
	out << settings_choice('${settings_action_side}0', 'Right', settings_padding, y, half,
		settings.button_side == .right)
	out << settings_choice('${settings_action_side}1', 'Left (macOS)', settings_padding +
		half + settings_row_gap, y, half, settings.button_side == .left)
	y += 28 + 22

	out << settings_heading('Taskbar', y, width)
	y += 22
	out << settings_note('One entry per window, or one per application.', y, width)
	y += 22
	out << settings_choice('${settings_action_taskbar}0', 'Standard', settings_padding,
		y, half, settings.taskbar_mode == .standard)
	out << settings_choice('${settings_action_taskbar}1', 'Combined', settings_padding +
		half + settings_row_gap, y, half, settings.taskbar_mode == .combined)
	y += 28 + 6
	out << settings_note(if settings.taskbar_mode == .combined {
		'Windows 7 style: one button per application.'
	} else {
		'Windows XP style: one button per window.'
	}, y, width)

	return out
}

fn (a &SettingsApp) theme_pane(width int) []ui2.Element {
	settings := a.desktop.settings
	inner := width - 2 * settings_padding
	half := (inner - settings_row_gap) / 2

	mut out := []ui2.Element{}
	mut y := settings_padding

	out << settings_heading('Theme', y, width)
	y += 22
	out << settings_note('How windows and the taskbar are drawn.', y, width)
	y += 22
	out << settings_choice('${settings_action_theme}0', 'Default', settings_padding, y,
		half, settings.theme == .default_)
	out << settings_choice('${settings_action_theme}1', 'macOS', settings_padding + half +
		settings_row_gap, y, half, settings.theme == .macos)
	y += 28 + 10

	if settings.theme == .macos {
		out << settings_note('Light grey windows with the title centred, three', y, width)
		y += 16
		out << settings_note('coloured discs at the leading edge, and a dock.', y, width)
	} else {
		out << settings_note('Rounded windows with shadows and flat colour,', y, width)
		y += 16
		out << settings_note('and a taskbar across the bottom.', y, width)
	}

	return out
}

fn (a &SettingsApp) wallpaper_pane(width int) []ui2.Element {
	settings := a.desktop.settings
	inner := width - 2 * settings_padding

	mut out := []ui2.Element{}
	mut y := settings_padding

	out << settings_heading('Colour', y, width)
	y += 24

	// Colour swatches, four to a row.
	columns := 4
	swatch := (inner - (columns - 1) * settings_row_gap) / columns
	for index, color in wallpaper_colors {
		column := index % columns
		row := index / columns
		selected := settings.wallpaper_image < 0 && settings.wallpaper_color == index
		out << ui2.clickable_view('${settings_action_color}${index}', ui2.rect(f64(settings_padding +
			column * (swatch + settings_row_gap)), f64(y + row * (swatch + settings_row_gap)),
			f64(swatch), f64(swatch)), ui2.BoxStyle{
			bg: if selected { app_accent } else { settings_choice_bg }
			radius: 6
		}, [
			// The swatch proper, inset so the selected ring shows around it.
			ui2.view('', ui2.rect(3, 3, f64(swatch - 6), f64(swatch - 6)), ui2.BoxStyle{
				bg: color.top
				radius: 4
			}, []),
		])
	}
	rows := (wallpaper_colors.len + columns - 1) / columns
	y += rows * (swatch + settings_row_gap) + 6

	out << settings_heading('Photo', y, width)
	y += 24

	if a.images.len == 0 {
		out << settings_note('No photographs on this image. The build downloads', y, width)
		y += 16
		out << settings_note('them; it had neither network nor cache.', y, width)
		return out
	}

	// Thumbnails, five to a row. They are drawn as plain tiles rather than as
	// the pictures themselves: scaling ten wallpapers every frame to fill
	// squares this size would cost more than the desktop it is describing.
	photo_columns := 5
	tile_width := (inner - (photo_columns - 1) * settings_row_gap) / photo_columns
	tile_height := tile_width * 3 / 4
	for index, _ in a.images {
		column := index % photo_columns
		row := index / photo_columns
		selected := settings.wallpaper_image == index
		out << ui2.clickable_view('${settings_action_image}${index}', ui2.rect(f64(settings_padding +
			column * (tile_width + settings_row_gap)), f64(y + row * (tile_height + settings_row_gap)),
			f64(tile_width), f64(tile_height)), ui2.BoxStyle{
			bg: if selected { app_accent } else { settings_choice_bg }
			radius: 6
		}, [
			ui2.label('', '${index + 1}', ui2.rect(0, 0, f64(tile_width), f64(tile_height)),
				ui2.TextStyle{
				color: if selected { app_on_accent } else { body_text }
				size: 12
				align: .center
			}),
		])
	}

	return out
}

fn (mut a SettingsApp) handle(event_id string) ! {
	if event_id.starts_with(settings_action_category) {
		index := event_id[settings_action_category.len..].int()
		if index >= 0 && index < settings_categories.len {
			a.category = settings_categories[index]
			// Entering either device pane reads it once, rather than leaving
			// the pane blank until the next poll comes round.
			match a.category {
				.battery { a.battery_read(true) }
				.wifi {
					a.wifi_action_result = WifiResult.ok
					a.refresh_wifi()
				}
				.display {
					a.write_result = BacklightResult.ok
					a.refresh()
				}
				else {}
			}
		}
		return
	}
	if a.category == .wifi {
		a.handle_wifi(event_id)
		return
	}
	if a.category == .display || a.category == .battery {
		a.handle_device(event_id)
		return
	}
	// Everything below writes a preference, which needs a desktop to write to.
	if a.desktop == unsafe { nil } {
		return
	}
	if event_id.starts_with(settings_action_side) {
		a.desktop.settings.button_side = if event_id.ends_with('1') {
			ButtonSide.left
		} else {
			ButtonSide.right
		}
		return
	}
	if event_id.starts_with(settings_action_taskbar) {
		a.desktop.settings.taskbar_mode = if event_id.ends_with('1') {
			TaskbarMode.combined
		} else {
			TaskbarMode.standard
		}
		return
	}
	if event_id.starts_with(settings_action_theme) {
		a.desktop.settings.theme = if event_id.ends_with('1') {
			ThemeKind.macos
		} else {
			ThemeKind.default_
		}
		return
	}
	if event_id.starts_with(settings_action_color) {
		index := event_id[settings_action_color.len..].int()
		if index >= 0 && index < wallpaper_colors.len {
			a.desktop.settings.wallpaper_color = index
			a.desktop.settings.wallpaper_image = -1
			a.desktop.invalidate_wallpaper()
		}
		return
	}
	if event_id.starts_with(settings_action_image) {
		index := event_id[settings_action_image.len..].int()
		if index >= 0 && index < a.images.len {
			a.desktop.settings.wallpaper_image = index
			a.desktop.invalidate_wallpaper()
		}
		return
	}
}
