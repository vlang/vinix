// Copyright (c) 2026 Alexander Medvednikov. All rights reserved.
// Use of this source code is governed by a GPL v2 license
// that can be found in the LICENSE file.

// SPDX-License-Identifier: GPL-2.0-or-later
// First-run application choice. Right after the user is created, setup offers
// the optional applications the image does not carry. The chosen ones are
// handed to the first Terminal, which installs them through pkg where their
// download progress and any network error remain visible.
module main

import math
import os
import ui2

// Registration leaves this marker in the persistent home before saving the
// user, so a restart between creating the user and choosing apps still shows
// the choice. Profiles created before the picker existed have no marker.
const app_selection_pending_name = '.vinix-first-run-apps'

// The Terminal claims and removes this one-shot request. It is volatile on
// purpose: an install the machine never got to is not replayed on later boots.
const app_selection_request_path = '/run/vinix-first-run-install'

const action_apps_install = 'apps.install'
const action_apps_open_source = 'apps.open_source_only'
const app_selection_filter_focus = -2

const app_selection_row_height = 40
const app_selection_row_top = 64
const app_selection_row_gap = 4
const app_selection_column_gap = 12
const app_selection_heading_height = 22
const app_selection_category_gap = 16
const action_apps_scrollbar = 'apps.scrollbar'
const app_selection_selected_bg = u32(0xeef4fd)
const app_selection_selected_border = u32(0x3975bd)
const app_selection_installed_bg = u32(0xf5f6f8)

// One install-button label per count of chosen apps, each a whole
// translation: the tree is rebuilt on every input and nothing collects the
// strings a formatted count would allocate.
enum AppSelectionInstallLabel {
	continue_
	install_1
	install_2
	install_3
	install_4
	install_many
}

const app_selection_install_labels = [AppSelectionInstallLabel.continue_, .install_1, .install_2,
	.install_3, .install_4, .install_many]

fn (l AppSelectionInstallLabel) text() string {
	return match l {
		.continue_ { tr('app_selection.continue') }
		.install_1 { tr('app_selection.install_1') }
		.install_2 { tr('app_selection.install_2') }
		.install_3 { tr('app_selection.install_3') }
		.install_4 { tr('app_selection.install_4') }
		.install_many { tr('app_selection.install_many') }
	}
}

// FirstRunApp is one optional application offered during setup. Any one of
// `installed_paths` being executable means the image already carries it. The
// title is a product name; detail_text says what it is in the desktop's
// language. VOffice is published for AArch64, pkg's Minecraft install uses
// AArch64 natives, and the native iOS runner requires ARM64 hardware.
struct FirstRunApp {
	title           string
	icon            string
	package_name    string
	action          string
	installed_paths []string
	arm64_only      bool
	open_source     bool // The offered application has an open-source license.
	category        FirstRunCategory
	requirement     FirstRunRequirement
}

// The apps this machine can install, in the order they are offered.
const first_run_apps = first_run_app_choices()

fn first_run_app_choices() []FirstRunApp {
	mut apps := []FirstRunApp{cap: first_run_app_catalogue.len}
	for app in first_run_app_catalogue {
		$if !arm64 {
			if app.arm64_only {
				continue
			}
		}
		apps << app
	}
	return apps
}

fn (app FirstRunApp) detail_text() string {
	return match app.package_name {
		'firefox' { tr('app_selection.firefox.detail') }
		'chromium' { tr('app_selection.chromium.detail') }
		'voffice' { tr('app_selection.voffice.detail') }
		'minecraft' { tr('app_selection.minecraft.detail') }
		'blender' { tr('app_selection.blender.detail') }
		'vlc-qt' { tr('app_selection.vlc.detail') }
		'mpv' { tr('app_selection.mpv.detail') }
		'vscodium' { tr('app_selection.vscodium.detail') }
		'zed' { tr('app_selection.zed.detail') }
		'neovim' { tr('app_selection.neovim.detail') }
		'keepassxc' { tr('app_selection.keepassxc.detail') }
		'discord' { tr('app_selection.discord.detail') }
		'telegram-desktop' { tr('app_selection.telegram.detail') }
		'slack' { tr('app_selection.slack.detail') }
		'spotify' { tr('app_selection.spotify.detail') }
		'obs-studio' { tr('app_selection.obs.detail') }
		'steam' { tr('app_selection.steam.detail') }
		'ios-runtime' { tr('app_selection.ios.detail') }
		else { '' }
	}
}

fn first_run_app_installed(app FirstRunApp) bool {
	for path in app.installed_paths {
		if C.access(&char(path.str), C.X_OK) == 0 {
			return true
		}
	}
	return false
}

fn app_selection_pending_path(home string) string {
	return '${home}/${app_selection_pending_name}'
}

fn desktop_mark_app_selection_pending(home string) bool {
	path := app_selection_pending_path(home)
	defer { unsafe { path.free() } }
	os.write_file(path, 'pending\n') or { return false }
	return true
}

fn desktop_app_selection_pending(home string) bool {
	path := app_selection_pending_path(home)
	defer { unsafe { path.free() } }
	return os.is_file(path)
}

fn desktop_finish_app_selection(home string) {
	path := app_selection_pending_path(home)
	defer { unsafe { path.free() } }
	os.rm(path) or {
		eprintln('vinix-desktop: could not clear the first-run app marker: ${err}')
		return
	}
	$if vinix {
		C.sync()
	}
}

struct AppSelectionState {
mut:
	selected           []bool
	installed          []bool
	available          []bool
	focus              int
	complete           bool
	open_source_only   bool
	scroll             int
	viewport_height    int
	columns            int = 1
	reveal_focus       bool = true
	scroll_drag        bool
	scroll_drag_offset int
}

fn new_app_selection_state() AppSelectionState {
	mut state := AppSelectionState{
		selected:  []bool{len: first_run_apps.len}
		installed: []bool{len: first_run_apps.len}
		available: []bool{len: first_run_apps.len}
	}
	for i, app in first_run_apps {
		state.installed[i] = first_run_app_installed(app)
		// Installation resolves an Alpine package or the official download on
		// demand. Repository configuration must not disable a setup choice.
		state.available[i] = true
	}
	state.set_focus(state.next_available(-1, 1))
	return state
}

fn (mut s AppSelectionState) close() {
	unsafe {
		s.selected.free()
		s.installed.free()
		s.available.free()
	}
}

fn (s &AppSelectionState) all_installed() bool {
	for installed in s.installed {
		if !installed {
			return false
		}
	}
	return true
}

fn (s &AppSelectionState) visible(index int) bool {
	return !s.open_source_only || first_run_apps[index].open_source
}

fn (s &AppSelectionState) selected_count() int {
	mut count := 0
	for i, selected in s.selected {
		if selected && s.visible(i) && !s.installed[i] && s.available[i] {
			count++
		}
	}
	return count
}

// packages lists the pkg names to install, in the order they are offered.
fn (s &AppSelectionState) packages() []string {
	mut packages := []string{cap: first_run_apps.len}
	for i, app in first_run_apps {
		if s.selected[i] && s.visible(i) && !s.installed[i] && s.available[i] {
			packages << app.package_name
		}
	}
	return packages
}

// next_available walks visible choices, wrapping around. -1 means there is
// no visible app left to install; the filter remains keyboard-accessible.
fn (s &AppSelectionState) next_available(from int, step int) int {
	count := first_run_app_order.len
	mut position := if step > 0 { -1 } else { 0 }
	for i, index in first_run_app_order {
		if index == from { position = i; break }
	}
	for offset in 1 .. count + 1 {
		index := first_run_app_order[((position + step * offset) % count + count) % count]
		if s.visible(index) && !s.installed[index] && s.available[index] {
			return index
		}
	}
	return -1
}

fn (s &AppSelectionState) next_vertical(step int) int {
	if s.focus < 0 { return s.next_available(-1, step) }
	y := s.row_y(s.focus, s.columns)
	column := s.column(s.focus, s.columns)
	mut best := -1
	mut distance := int(0x7fffffff)
	for i in 0 .. first_run_apps.len {
		if !s.visible(i) || s.installed[i] || !s.available[i] { continue }
		delta := (s.row_y(i, s.columns) - y) * step
		if delta <= 0 { continue }
		score := delta * s.columns + abs_int(s.column(i, s.columns) - column)
		if score < distance {
			best = i
			distance = score
		}
	}
	return if best >= 0 { best } else { s.next_available(-1, step) }
}

fn (mut s AppSelectionState) toggle(index int) {
	if index < 0 || index >= first_run_apps.len || s.installed[index] || !s.available[index] {
		return
	}
	if !s.visible(index) { return }
	s.selected[index] = !s.selected[index]
	s.set_focus(index)
}

fn (mut s AppSelectionState) set_focus(index int) {
	s.focus = index
	s.reveal_focus = true
}

fn (mut s AppSelectionState) handle_action(action string) {
	if action == action_apps_open_source {
		s.open_source_only = !s.open_source_only
		s.scroll = 0
		s.scroll_drag = false
		s.set_focus(app_selection_filter_focus)
		return
	}
	if action == action_apps_install {
		s.complete = true
		return
	}
	for i, app in first_run_apps {
		if action == app.action {
			s.toggle(i)
			return
		}
	}
}

// Setup keeps owning the keyboard: arrows and Tab move between apps, Space or
// a row's number toggles it and Return confirms. Other escape sequences and
// control chords are discarded rather than reaching desktop shortcuts.
fn (mut s AppSelectionState) key_input(keys string) {
	mut i := 0
	for i < keys.len {
		ch := keys[i]
		if ch == 0x1b {
			if i + 2 < keys.len && (keys[i + 1] == `[` || keys[i + 1] == `O`) {
				match keys[i + 2] {
					`A` { s.set_focus(s.next_vertical(-1)) }
					`B` { s.set_focus(s.next_vertical(1)) }
					`D` { s.set_focus(s.next_available(s.focus, -1)) }
					`C` { s.set_focus(s.next_available(s.focus, 1)) }
					`H` { s.set_focus(s.next_available(-1, 1)) }
					`F` { s.set_focus(s.next_available(-1, -1)) }
					`Z` {
						if s.next_available(-1, 1) < 0 || s.focus == s.next_available(-1, 1) {
							s.set_focus(app_selection_filter_focus)
						} else {
							s.set_focus(s.next_available(s.focus, -1))
						}
					}
					else {}
				}
			}
			return
		}
		match ch {
			9 {
				next := s.next_available(s.focus, 1)
				s.set_focus(if next < 0 || (s.focus != app_selection_filter_focus && next == s.next_available(-1, 1)) {
					app_selection_filter_focus
				} else { next })
			}
			` ` {
				if s.focus == app_selection_filter_focus {
					s.handle_action(action_apps_open_source)
				} else {
					s.toggle(s.focus)
				}
			}
			`\n`, `\r` {
				s.complete = true
				return
			}
			else {
				if ch >= `1` && ch <= `9` && int(ch - `1`) < first_run_apps.len {
					s.toggle(int(ch - `1`))
				}
			}
		}
		i++
	}
}

// Desktop views paint a fill only. A border is therefore an outer fill in the
// border colour with the content's own fill inset one pixel inside it.
fn app_selection_bordered(id string, frame ui2.Rect, radius int, border_color u32, bg u32,
	children []ui2.Element) ui2.Element {
	inner := ui2.view('', ui2.rect(1, 1, frame.width - 2, frame.height - 2), ui2.BoxStyle{
		bg:     bg
		radius: radius - 1
	}, children)
	return ui2.view(id, frame, ui2.BoxStyle{
		bg:     border_color
		radius: radius
	}, frame_child(inner))
}

// Setup draws its own controls before a desktop theme has been chosen.
fn app_selection_filter(checked bool, label string, frame ui2.Rect, style ui2.TextStyle) ui2.Element {
	mut children := frame_elements(2)
	mut mark := frame_elements(1)
	if checked {
		icon := ui2.image('', 'builtin:check', ui2.rect(0, 0, 14, 14))
		mark << ui2.Element{ ...icon, text_style: ui2.TextStyle{ color: app_on_accent } }
	}
	children << app_selection_bordered('', ui2.rect(0, 5, 16, 16), 4,
		if checked { app_accent } else { body_muted },
		if checked { app_accent } else { registration_field_bg }, mark)
	children << ui2.label('', label, ui2.rect(24, 0, frame.width - 24, 26), style)
	return ui2.Element{
		...ui2.clickable_view(action_apps_open_source, frame, ui2.BoxStyle{ transparent: true }, children)
		checked: checked
		accessibility_role: 'checkbox'
		accessibility_label: label
	}
}

fn app_selection_row(app FirstRunApp, installed bool, available bool, selected bool, hovered bool, x int, y int,
	width int, height int) ui2.Element {
	// Child coordinates are inside the one-pixel border.
	mut children := frame_elements(4)
	icon := ui2.image('', app.icon, ui2.rect(9, f64((height - 28) / 2), 28, 28))
	// Bundled artwork ignores the colour; a builtin glyph is drawn in it.
	children << ui2.Element{
		...icon
		text_style: ui2.TextStyle{
			color: app_accent
		}
	}
	title_color := if installed || !available { body_muted } else { body_heading }
	compact_installed := installed && width < 240
	title_width := math.max(0, width - 60 - if installed && !compact_installed { 98 } else { 0 })
	title_y := if app.package_name == 'ios-runtime' || compact_installed { 0 } else { (height - 22) / 2 }
	children << ui2.label('', app.title, ui2.rect(47, f64(title_y), f64(title_width), 22),
		ui2.TextStyle{
			color: title_color
			size:  14
			bold:  true
		})
	if app.package_name == 'ios-runtime' && !compact_installed {
		children << ui2.label('', app.detail_text(), ui2.rect(47, 20, f64(title_width), 16),
			ui2.TextStyle{ color: body_muted, size: 10 })
	}
	if installed {
		status_frame := if compact_installed {
			ui2.rect(47, 22, f64(title_width), 16)
		} else {
			ui2.rect(f64(width - 111), f64((height - 20) / 2), 94, 20)
		}
		children << ui2.label('', tr('app_selection.installed'), status_frame,
			ui2.TextStyle{
				color: body_muted
				size:  11
				align: if compact_installed { .left } else { .right }
			})
	}
	mut background := registration_field_bg
	if installed || !available {
		background = app_selection_installed_bg
	} else if selected {
		background = app_selection_selected_bg
	}
	row := app_selection_bordered(app.action, ui2.rect(f64(x), f64(y), f64(width),
		f64(height)), 8,
		if selected { app_selection_selected_border } else if hovered { app_accent } else { body_rule },
		background, children)
	// The whole row is the hit target, so clicking an app's name or icon picks it.
	return ui2.Element{
		...row
		clickable: !installed && available
		enabled:   !installed && available
	}
}

struct AppSelectionLayout {
	x           int
	y           int
	width       int
	height      int
	list_top    int
	list_height int
	columns     int
}

fn app_selection_layout(width int, height int) AppSelectionLayout {
	mut card_width := 1000
	if card_width > width - 24 {
		card_width = width - 24
	}
	if card_width < 1 {
		card_width = 1
	}
	mut card_height := 680
	if card_height > height - 48 {
		card_height = height - 48
	}
	if card_height < 1 {
		card_height = 1
	}
	list_top := app_selection_row_top + if card_width < 960 { 28 } else { 0 }
	return AppSelectionLayout{
		x: (width - card_width) / 2
		y: (height - card_height) / 2
		width: card_width
		height: card_height
		list_top: list_top
		list_height: math.max(1, card_height - list_top - 64)
		columns: if card_width >= 960 { 3 } else if card_width >= 720 { 2 } else { 1 }
	}
}

fn (s &AppSelectionState) category_rows(category FirstRunCategory, columns int) int {
	mut count := 0
	for i, app in first_run_apps {
		if app.category == category && s.visible(i) { count++ }
	}
	return (count + columns - 1) / columns
}

fn (s &AppSelectionState) content_height(columns int) int {
	mut height := 0
	for category in first_run_categories {
		rows := s.category_rows(category, columns)
		if rows == 0 { continue }
		height += app_selection_heading_height + app_selection_category_gap
		height += rows * (app_selection_row_height + app_selection_row_gap)
	}
	return math.max(0, height - app_selection_row_gap - app_selection_category_gap)
}

fn (s &AppSelectionState) column(index int, columns int) int {
	mut position := 0
	for i, app in first_run_apps {
		if !s.visible(i) { continue }
		if i == index { return position % columns }
		if app.category == first_run_apps[index].category { position++ }
	}
	return 0
}

fn (s &AppSelectionState) row_y(index int, columns int) int {
	mut y := 0
	for category in first_run_categories {
		rows := s.category_rows(category, columns)
		if rows == 0 { continue }
		y += app_selection_heading_height
		mut position := 0
		for i, app in first_run_apps {
			if app.category != category || !s.visible(i) { continue }
			if i == index { return y + position / columns * (app_selection_row_height + app_selection_row_gap) }
			position++
		}
		y += rows * (app_selection_row_height + app_selection_row_gap)
		y += app_selection_category_gap
	}
	return -1
}

fn (mut s AppSelectionState) scroll_to(offset int) {
	s.scroll = math.max(0, math.min(offset, s.content_height(s.columns) - s.viewport_height))
	s.reveal_focus = false
}

fn (mut s AppSelectionState) prepare_viewport(height int, columns int) {
	s.reveal_focus = s.reveal_focus || s.columns != columns || s.viewport_height != height
	s.viewport_height = height
	s.columns = columns
	s.scroll = math.max(0, math.min(s.scroll, s.content_height(columns) - height))
	if s.reveal_focus && s.focus >= 0 {
		y := s.row_y(s.focus, columns)
		if y < s.scroll {
			// Keep the category heading when moving to its first app.
			s.scroll = math.max(0, y - app_selection_heading_height)
		} else if y + app_selection_row_height > s.scroll + height {
			s.scroll = y + app_selection_row_height - height
		}
	}
	s.reveal_focus = false
}

fn (s &AppSelectionState) scrollbar_thumb() (int, int) {
	content := s.content_height(s.columns)
	height := s.viewport_height
	thumb := math.min(height, math.max(24, height * height / math.max(1, content)))
	travel := height - thumb
	return if content > height { s.scroll * travel / (content - height) } else { 0 }, thumb
}

fn (mut s AppSelectionState) element(d &Desktop) ui2.Element {
	layout := app_selection_layout(d.canvas.width, d.canvas.height)
	card_width := layout.width
	card_height := layout.height
	card_x := layout.x
	card_y := layout.y
	inner := card_width - 48
	grid_width := inner - 16
	row_width := (grid_width - (layout.columns - 1) * app_selection_column_gap) / layout.columns / 2
	s.prepare_viewport(layout.list_height, layout.columns)

	mut card_children := frame_elements(24)
	filter_label := tr('app_selection.open_source_only')
	filter_style := ui2.TextStyle{ color: body_heading, size: 13 }
	filter_text_width := if d.fonts.len > 0 { d.face_for(filter_style).text_width(filter_label) } else { 332 }
	filter_width := math.min(inner, filter_text_width + 24)
	filter_x := card_width - 24 - filter_width
	filter_y := if layout.list_top == app_selection_row_top { 20 } else { 50 }
	title_width := if layout.list_top == app_selection_row_top { inner - filter_width - 16 } else { inner }
	card_children << ui2.label('apps.title', tr('app_selection.intro'), ui2.rect(24, 16, f64(title_width),
		34), ui2.TextStyle{
		color: body_heading
		size:  24
		bold:  true
	})
	if s.focus == app_selection_filter_focus {
		card_children << app_selection_bordered('apps.filter.focus',
			ui2.rect(f64(filter_x - 4), f64(filter_y - 2), f64(filter_width + 8), 30),
			6, app_accent, registration_card, []ui2.Element{})
	}
	card_children << app_selection_filter(s.open_source_only, filter_label,
		ui2.rect(f64(filter_x), f64(filter_y), f64(filter_width), 26),
		filter_style)
	mut list_children := frame_elements(first_run_apps.len * 2 + first_run_categories.len)
	mut y := -s.scroll
	for category_index, category in first_run_categories {
		rows := s.category_rows(category, layout.columns)
		if rows == 0 { continue }
		list_children << ui2.label(first_run_category_headers[category_index], category.text(),
			ui2.rect(1, f64(y), f64(grid_width), 18), ui2.TextStyle{
				color: body_heading
				size: 14
				bold: true
			})
		y += app_selection_heading_height
		mut position := 0
		for i, app in first_run_apps {
			if app.category != category || !s.visible(i) { continue }
			x := 1 + position % layout.columns * (row_width + app_selection_column_gap)
			row_y := y + position / layout.columns * (app_selection_row_height + app_selection_row_gap)
			position++
			if row_y < layout.list_height && row_y + app_selection_row_height > 0 {
				if s.focus == i {
					list_children << ui2.view('apps.focus', ui2.rect(f64(x - 1), f64(row_y - 1), f64(row_width + 2),
						app_selection_row_height + 2), ui2.BoxStyle{
							bg: if s.selected[i] { app_selection_selected_border } else { app_accent }
							radius: 9
						}, []ui2.Element{})
				}
				// Crop the hit target as well as its pixels at the viewport edges.
				top := math.max(0, row_y)
				bottom := math.min(layout.list_height, row_y + app_selection_row_height)
				row := app_selection_row(app, s.installed[i], s.available[i], s.selected[i],
					d.hover == app.action, 0, row_y - top, row_width, app_selection_row_height)
				content := ui2.Element{ ...row, id: '', clickable: false }
				list_children << ui2.Element{
					...ui2.view(app.action, ui2.rect(f64(x), f64(top), f64(row_width), f64(bottom - top)),
						ui2.BoxStyle{ transparent: true }, frame_child(content))
					clickable: row.clickable
					enabled: row.enabled
				}
			}
		}
		y += rows * (app_selection_row_height + app_selection_row_gap)
		y += app_selection_category_gap
	}
	card_children << ui2.view('apps.list', ui2.rect(24, f64(layout.list_top), f64(inner),
		f64(layout.list_height)), ui2.BoxStyle{ bg: registration_card }, list_children)
	if s.content_height(s.columns) > layout.list_height {
		thumb_y, thumb_height := s.scrollbar_thumb()
		thumb := ui2.view('', ui2.rect(0, f64(thumb_y), 6, f64(thumb_height)),
			ui2.BoxStyle{ bg: body_muted, radius: 3 }, []ui2.Element{})
		card_children << ui2.clickable_view(action_apps_scrollbar,
			ui2.rect(f64(card_width - 30), f64(layout.list_top), 6, f64(layout.list_height)),
			ui2.BoxStyle{ bg: body_rule, radius: 3 }, frame_child(thumb))
	}
	mut count := s.selected_count()
	if count >= app_selection_install_labels.len {
		count = app_selection_install_labels.len - 1
	}
	label := app_selection_install_labels[count].text()
	button_width := math.min(inner, if count == 0 { 112 } else { 192 })
	card_children << ui2.label('apps.note', tr('app_selection.note'),
		ui2.rect(24, f64(card_height - 42), f64(inner - button_width - 16), 20), ui2.TextStyle{
			color: body_muted
			size:  11
		})
	card_children << ui2.button(action_apps_install, label,
		ui2.rect(f64(card_width - 24 - button_width), f64(card_height - 48), f64(button_width), 32),
		ui2.BoxStyle{
			bg:     if d.hover == action_apps_install { u32(0x4a8ee7) } else { app_accent }
			radius: 6
		}, ui2.TextStyle{
			color: app_on_accent
			size:  13
			bold:  true
			align: .center
		})

	mut screen_children := frame_elements(1)
	screen_children << ui2.view('apps.window', ui2.rect(f64(card_x), f64(card_y),
		f64(card_width), f64(card_height)), ui2.BoxStyle{
		bg:            registration_card
		radius:        12
		border_color:  body_rule
		border_left:   1
		border_top:    1
		border_right:  1
		border_bottom: 1
	}, card_children)
	return ui2.screen(registration_backdrop, screen_children)
}

fn (mut s AppSelectionState) poll_pointer(mut d Desktop, mut pointer PointerDevice) bool {
	packet := pointer.poll() or { return false }
	if packet.max_x <= 0 || packet.max_y <= 0 {
		d.pointer_present = false
		return true
	}
	d.pointer_present = true
	d.pointer_x = int(i64(packet.x) * i64(d.canvas.width - 1) / i64(packet.max_x))
	d.pointer_y = int(i64(packet.y) * i64(d.canvas.height - 1) / i64(packet.max_y))
	d.buttons = packet.buttons
	d.set_hover(d.hit_action(d.pointer_x, d.pointer_y))
	s.pointer_input(packet, d)
	return true
}

fn (mut s AppSelectionState) pointer_input(packet PointerPacket, d &Desktop) {
	layout := app_selection_layout(d.canvas.width, d.canvas.height)
	s.prepare_viewport(layout.list_height, layout.columns)
	list_y := layout.y + layout.list_top
	if packet.released & button_left != 0 || packet.buttons & button_left == 0 {
		s.scroll_drag = false
	}
	if packet.scroll != 0 && d.pointer_x >= layout.x + 24
		&& d.pointer_x < layout.x + layout.width - 24
		&& d.pointer_y >= list_y && d.pointer_y < list_y + layout.list_height {
		s.scroll_to(s.scroll - int(packet.scroll) * 36)
		return
	}
	if packet.pressed & button_left != 0 {
		if d.hover == action_apps_scrollbar {
			thumb_y, thumb_height := s.scrollbar_thumb()
			position := d.pointer_y - list_y
			s.scroll_drag_offset = if position >= thumb_y && position < thumb_y + thumb_height {
				position - thumb_y
			} else {
				thumb_height / 2
			}
			s.scroll_drag = true
		} else {
			s.handle_action(d.hover)
		}
	}
	if s.scroll_drag {
		_, thumb_height := s.scrollbar_thumb()
		travel := layout.list_height - thumb_height
		if travel > 0 {
			position := d.pointer_y - list_y - s.scroll_drag_offset
			s.scroll_to(position * (s.content_height(s.columns) - layout.list_height) / travel)
		}
	}
}

// desktop_request_first_run_install hands the chosen pkg names to the next
// Terminal. Only names setup itself offers are written.
fn desktop_request_first_run_install(packages []string) bool {
	if packages.len == 0 {
		return false
	}
	request := packages.join(' ') + '\n'
	defer { unsafe { request.free() } }
	return desktop_write_file(app_selection_request_path, request.str, u64(request.len))
}

// desktop_take_first_run_install claims a pending setup request and returns
// the shell command that installs it, or '' when there is none.
fn desktop_take_first_run_install() string {
	if !os.is_file(app_selection_request_path) {
		return ''
	}
	request := os.read_file(app_selection_request_path) or { return '' }
	os.rm(app_selection_request_path) or {}
	defer { unsafe { request.free() } }
	return first_run_install_command(request)
}

// first_run_install_command turns a request into the Terminal's command. Only
// names setup itself offers survive, and each app is installed separately so
// one failed download does not skip the others.
fn first_run_install_command(request string) string {
	words := request.fields()
	mut packages := []string{cap: first_run_apps.len}
	for word in words {
		for app in first_run_apps {
			if word == app.package_name && app.package_name !in packages {
				packages << app.package_name
			}
		}
	}
	unsafe { words.free() }
	if packages.len == 0 {
		unsafe { packages.free() }
		return ''
	}
	names := packages.join(' ')
	defer {
		unsafe {
			names.free()
			packages.free()
		}
	}
	// The messages sit inside the shell's quotes: `$failed` is the shell's list
	// of what failed, and no translation contains a quote, `$`, `\` or a
	// backtick (tools/tests/i18n_apps_test.v).
	started := tr_fill('app_selection.install.started', names)
	not_installed := tr_fill('app_selection.install.failed', '\$failed')
	done := tr('app_selection.install.done')
	defer {
		unsafe {
			started.free()
			not_installed.free()
		}
	}
	return "echo '${started}'; echo; " +
		'failed=; for app in ${names}; do ' +
		'case "\$app" in ios-runtime) /usr/bin/vinix-desktop --install-ios-runtime && ' +
		'{ if [ -x /usr/libexec/vinix-persist-packages ]; then /usr/libexec/vinix-persist-packages save; fi; } ;; ' +
		'vscodium|zed|discord|slack|spotify|steam) /usr/bin/vinix-desktop --install-setup-app "\$app" ;; ' +
		'libreoffice) pkg install "\$app" libreoffice-gtk libreoffice-lang-en_us ttf-liberation font-dejavu adwaita-icon-theme ;; ' +
		'vlc-qt|keepassxc) pkg install "\$app" qt5-qtbase-x11 font-dejavu ;; ' +
		'telegram-desktop) pkg install "\$app" qt6-qtbase-x11 font-dejavu ;; ' +
		'*) pkg install "\$app" ;; esac || failed="\$failed \$app"; done; echo; ' +
		'if [ -n "\$failed" ]; then echo "${not_installed}"; ' +
		"else echo '${done}'; fi; " + 'exec /bin/zsh -i'
}

// The picker runs between registration and the first ordinary desktop frame,
// with the same exclusive ownership of the display and input. It returns
// whether a Terminal should be opened to install the chosen apps.
fn (mut d Desktop) choose_first_run_apps(mut fb Framebuffer, mut pointer PointerDevice,
	mut keyboard Keyboard, frame_interval i64, idle_interval i64) bool {
	if !desktop_app_selection_pending(desktop_home) {
		return false
	}
	// Without pkg nothing on offer can be installed, and with everything
	// already present there is nothing to choose.
	mut selection := new_app_selection_state()
	defer { selection.close() }
	if C.access(c'/usr/bin/pkg', C.X_OK) != 0 || selection.all_installed() {
		desktop_finish_app_selection(desktop_home)
		return false
	}
	mut dirty := true
	for !selection.complete {
		if !dirty {
			desktop_wait_for_input(pointer.fd, keyboard.fd, idle_interval)
		}
		power := desktop_pending_power_action()
		if power == .reload_desktop {
			d.end_session(power)
			return false
		}
		if power != .keep_running {
			desktop_power_apply(power)
		}
		if selection.poll_pointer(mut d, mut pointer) {
			dirty = true
		}
		keys := keyboard.poll()
		if keys.len > 0 {
			selection.key_input(keys)
			dirty = true
		}
		if selection.complete || !dirty {
			continue
		}
		frame_started := monotonic_millis()
		begin_frame_elements()
		tree := selection.element(d)
		d.render(tree)
		fb.present(&d.canvas, desktop_current_scale())
		free_tree(tree)
		dirty = false
		sleep_to_next_frame(frame_started, frame_interval)
	}
	d.reset_setup_input()
	packages := selection.packages()
	requested := desktop_request_first_run_install(packages)
	if packages.len > 0 && !requested {
		eprintln('vinix-desktop: could not hand the chosen apps to Terminal')
	}
	unsafe { packages.free() }
	desktop_finish_app_selection(desktop_home)
	return requested
}
