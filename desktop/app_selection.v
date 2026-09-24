// Copyright (c) 2026 Alexander Medvednikov. All rights reserved.
// Use of this source code is governed by a GPL v2 license
// that can be found in the LICENSE file.

// SPDX-License-Identifier: GPL-2.0-or-later
// First-run application choice. Right after the user is created, setup offers
// the optional applications the image does not carry. The chosen ones are
// handed to the first Terminal, which installs them through pkg where their
// download progress and any network error remain visible.
module main

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

const app_selection_row_height = 64
const app_selection_row_gap = 10
const app_selection_row_top = 104
const app_selection_selected_bg = u32(0xeef4fd)
const app_selection_installed_bg = u32(0xf5f6f8)

// Literal labels: the tree is rebuilt on every input and nothing collects the
// strings a formatted count would allocate.
const app_selection_install_labels = ['Continue', 'Install 1 app', 'Install 2 apps',
	'Install 3 apps', 'Install 4 apps']

// FirstRunApp is one optional application offered during setup. Any one of
// `installed_paths` being executable means the image already carries it.
struct FirstRunApp {
	title           string
	detail          string
	icon            string
	package_name    string
	action          string
	installed_paths []string
}

const first_run_apps = [
	FirstRunApp{
		title:           'Firefox'
		detail:          'Mozilla web browser'
		icon:            'asset:firefox'
		package_name:    'firefox'
		action:          'apps.toggle.firefox'
		installed_paths: ['/usr/lib/firefox-esr/firefox-esr', '/usr/lib/firefox/firefox']
	},
	FirstRunApp{
		title:           'Chromium'
		detail:          'The open-source Chrome web browser'
		icon:            'asset:chromium'
		package_name:    'chromium'
		action:          'apps.toggle.chromium'
		installed_paths: ['/usr/lib/chromium/chrome']
	},
	FirstRunApp{
		title:           'VOffice'
		detail:          'Writer documents and Calc spreadsheets'
		icon:            'builtin:editor'
		package_name:    'voffice'
		action:          'apps.toggle.voffice'
		installed_paths: ['/usr/bin/voffice-writer']
	},
	FirstRunApp{
		title:           'Minecraft'
		detail:          'Java Edition, with a Microsoft account'
		icon:            'asset:minecraft'
		package_name:    'minecraft'
		action:          'apps.toggle.minecraft'
		installed_paths: ['/usr/bin/minecraft']
	},
]

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
	selected  []bool
	installed []bool
	focus     int
	complete  bool
}

fn new_app_selection_state() AppSelectionState {
	mut state := AppSelectionState{
		selected:  []bool{len: first_run_apps.len}
		installed: []bool{len: first_run_apps.len}
	}
	for i, app in first_run_apps {
		state.installed[i] = first_run_app_installed(app)
	}
	state.focus = state.next_available(-1, 1)
	return state
}

fn (s &AppSelectionState) all_installed() bool {
	for installed in s.installed {
		if !installed {
			return false
		}
	}
	return true
}

fn (s &AppSelectionState) selected_count() int {
	mut count := 0
	for i, selected in s.selected {
		if selected && !s.installed[i] {
			count++
		}
	}
	return count
}

// packages lists the pkg names to install, in the order they are offered.
fn (s &AppSelectionState) packages() []string {
	mut packages := []string{cap: first_run_apps.len}
	for i, app in first_run_apps {
		if s.selected[i] && !s.installed[i] {
			packages << app.package_name
		}
	}
	return packages
}

// next_available walks from `from` in `step` direction to the next row that
// can still be chosen, wrapping around. -1 means every app is installed.
fn (s &AppSelectionState) next_available(from int, step int) int {
	count := first_run_apps.len
	for offset in 1 .. count + 1 {
		index := ((from + step * offset) % count + count) % count
		if !s.installed[index] {
			return index
		}
	}
	return -1
}

fn (mut s AppSelectionState) toggle(index int) {
	if index < 0 || index >= first_run_apps.len || s.installed[index] {
		return
	}
	s.selected[index] = !s.selected[index]
	s.focus = index
}

fn (mut s AppSelectionState) handle_action(action string) {
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
					`A` { s.focus = s.next_available(s.focus, -1) }
					`B` { s.focus = s.next_available(s.focus, 1) }
					else {}
				}
			}
			return
		}
		match ch {
			9 {
				s.focus = s.next_available(s.focus, 1)
			}
			` ` {
				s.toggle(s.focus)
			}
			`\n`, `\r` {
				s.complete = true
				return
			}
			else {
				if ch >= `1` && ch < `1` + u8(first_run_apps.len) {
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

fn app_selection_row(app FirstRunApp, installed bool, selected bool, hovered bool, y int,
	width int) ui2.Element {
	// Child coordinates are inside the one-pixel border.
	mut children := frame_elements(5)
	icon := ui2.image('', app.icon, ui2.rect(13, 13, 36, 36))
	// Bundled artwork ignores the colour; a builtin glyph is drawn in it.
	children << ui2.Element{
		...icon
		text_style: ui2.TextStyle{
			color: app_accent
		}
	}
	title_color := if installed { body_muted } else { body_heading }
	children << ui2.label('', app.title, ui2.rect(63, 11, f64(width - 64 - 112), 22),
		ui2.TextStyle{
		color: title_color
		size:  14
		bold:  true
	})
	children << ui2.label('', app.detail, ui2.rect(63, 33, f64(width - 64 - 112), 18),
		ui2.TextStyle{
		color: body_muted
		size:  11
	})
	if installed {
		children << ui2.label('', 'Installed', ui2.rect(f64(width - 111), 21, 94, 20),
			ui2.TextStyle{
			color: body_muted
			size:  11
			align: .right
		})
	} else {
		mut mark := frame_elements(1)
		if selected {
			check := ui2.image('', 'builtin:check', ui2.rect(0, 0, 20, 20))
			mark << ui2.Element{
				...check
				text_style: ui2.TextStyle{
					color: app_on_accent
				}
			}
		}
		children << app_selection_bordered('', ui2.rect(f64(width - 41), 20, 22, 22), 5,
			if selected || hovered { app_accent } else { body_rule },
			if selected { app_accent } else { registration_field_bg }, mark)
	}
	mut background := registration_field_bg
	if installed {
		background = app_selection_installed_bg
	} else if selected {
		background = app_selection_selected_bg
	}
	row := app_selection_bordered(app.action, ui2.rect(32, f64(y), f64(width),
		app_selection_row_height), 8, if hovered || selected { app_accent } else { body_rule },
		background, children)
	// The whole row is the hit target, so clicking an app's name or icon picks it.
	return ui2.Element{
		...row
		clickable: !installed
		enabled:   !installed
	}
}

fn (s &AppSelectionState) element(d &Desktop) ui2.Element {
	mut card_width := 520
	if card_width > d.canvas.width - 24 {
		card_width = d.canvas.width - 24
	}
	if card_width < 1 {
		card_width = 1
	}
	mut card_height := 500
	if card_height > d.canvas.height - 24 {
		card_height = d.canvas.height - 24
	}
	if card_height < 1 {
		card_height = 1
	}
	card_x := (d.canvas.width - card_width) / 2
	card_y := (d.canvas.height - card_height) / 2
	inner := card_width - 64

	mut card_children := frame_elements(9)
	card_children << ui2.label('apps.title', 'Choose your apps', ui2.rect(32, 28, f64(inner),
		34), ui2.TextStyle{
		color: body_heading
		size:  24
		bold:  true
	})
	card_children << ui2.label('apps.subtitle', 'Pick the apps to download and install now.',
		ui2.rect(32, 67, f64(inner), 24), ui2.TextStyle{
		color: body_muted
		size:  12
	})
	for i, app in first_run_apps {
		y := app_selection_row_top + i * (app_selection_row_height + app_selection_row_gap)
		if s.focus == i {
			// The keyboard focus ring thickens the row's border to two pixels.
			card_children << ui2.view('apps.focus', ui2.rect(31, f64(y - 1), f64(inner + 2),
				app_selection_row_height + 2), ui2.BoxStyle{
				bg:     app_accent
				radius: 9
			}, []ui2.Element{})
		}
		card_children << app_selection_row(app, s.installed[i], s.selected[i],
			d.hover == app.action, y, inner)
	}
	card_children << ui2.label('apps.note', 'You can install more later with pkg install in Terminal.',
		ui2.rect(32, 402, f64(inner), 20), ui2.TextStyle{
		color: body_muted
		size:  11
	})
	mut count := s.selected_count()
	if count >= app_selection_install_labels.len {
		count = app_selection_install_labels.len - 1
	}
	label := app_selection_install_labels[count]
	card_children << ui2.button(action_apps_install, label, ui2.rect(32, 432, f64(inner), 40),
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
	if packet.pressed & button_left != 0 {
		s.handle_action(d.hover)
	}
	return true
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
	return "echo 'Installing the apps chosen during setup: ${names}'; echo; " +
		"failed=; for app in ${names}; do pkg install \"\$app\" || failed=\"\$failed \$app\"; done; echo; " +
		"if [ -n \"\$failed\" ]; then echo \"Not installed:\$failed. Run pkg install\$failed to try again.\"; " +
		"else echo 'The selected apps are installed. Open them from the desktop or the Start menu.'; fi; " +
		'exec /bin/zsh -i'
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
