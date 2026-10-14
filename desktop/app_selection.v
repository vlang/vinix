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
const app_selection_row_top = 104
const app_selection_selected_bg = u32(0xeef4fd)
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
// language. `arm64_only` apps have no package for other architectures:
// VOffice is only published for AArch64, and pkg's Minecraft install uses
// AArch64 natives.
struct FirstRunApp {
	title           string
	icon            string
	package_name    string
	action          string
	installed_paths []string
	arm64_only      bool
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
	selected  []bool
	installed []bool
	available []bool
	category  FirstRunCategory
	focus     int
	complete  bool
}

fn new_app_selection_state() AppSelectionState {
	mut state := AppSelectionState{
		selected:  []bool{len: first_run_apps.len}
		installed: []bool{len: first_run_apps.len}
		available: []bool{len: first_run_apps.len}
	}
	repositories := os.read_file('/etc/apk/repositories') or { '' }
	testing := first_run_testing_repositories(repositories)
	unsafe { repositories.free() }
	for i, app in first_run_apps {
		state.installed[i] = first_run_app_installed(app)
		state.available[i] = match app.requirement {
			.alpine { true }
			.testing { testing }
			.ios { first_run_ios_payload_available() }
			else { false }
		}
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

fn (s &AppSelectionState) selected_count() int {
	mut count := 0
	for i, selected in s.selected {
		if selected && !s.installed[i] && s.available[i] {
			count++
		}
	}
	return count
}

// packages lists the pkg names to install, in the order they are offered.
fn (s &AppSelectionState) packages() []string {
	mut packages := []string{cap: first_run_apps.len}
	for i, app in first_run_apps {
		if s.selected[i] && !s.installed[i] && s.available[i] {
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
		if !s.installed[index] && s.available[index] {
			return index
		}
	}
	return -1
}

fn (mut s AppSelectionState) toggle(index int) {
	if index < 0 || index >= first_run_apps.len || s.installed[index] || !s.available[index] {
		return
	}
	s.selected[index] = !s.selected[index]
	s.set_focus(index)
}

fn (mut s AppSelectionState) set_focus(index int) {
	s.focus = index
	if index >= 0 { s.category = first_run_apps[index].category }
}

fn (mut s AppSelectionState) select_category(category FirstRunCategory) {
	s.category = category
	s.focus = -1
	for i, app in first_run_apps {
		if app.category == category && s.available[i] && !s.installed[i] {
			s.focus = i
			break
		}
	}
}

fn (mut s AppSelectionState) handle_action(action string) {
	if action == action_apps_install {
		s.complete = true
		return
	}
	for i, category in first_run_categories {
		if action == first_run_category_actions[i] {
			s.select_category(category)
			return
		}
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
					`A` { s.set_focus(s.next_available(s.focus, -1)) }
					`B` { s.set_focus(s.next_available(s.focus, 1)) }
					`C` {
						s.select_category(first_run_categories[(int(s.category) + 1) % first_run_categories.len])
					}
					`D` {
						s.select_category(first_run_categories[(int(s.category) + first_run_categories.len - 1) % first_run_categories.len])
					}
					else {}
				}
			}
			return
		}
		match ch {
			9 {
				s.set_focus(s.next_available(s.focus, 1))
			}
			` ` {
				s.toggle(s.focus)
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

fn app_selection_row(app FirstRunApp, installed bool, available bool, selected bool, hovered bool, x int, y int,
	width int, height int) ui2.Element {
	// Child coordinates are inside the one-pixel border.
	mut children := frame_elements(5)
	icon := ui2.image('', app.icon, ui2.rect(13, f64((height - 36) / 2), 36, 36))
	// Bundled artwork ignores the colour; a builtin glyph is drawn in it.
	children << ui2.Element{
		...icon
		text_style: ui2.TextStyle{
			color: app_accent
		}
	}
	title_color := if installed || !available { body_muted } else { body_heading }
	children << ui2.label('', app.title, ui2.rect(63, 9, f64(width - 76), 22),
		ui2.TextStyle{
			color: title_color
			size:  14
			bold:  true
		})
	detail := if !installed && !available { app.requirement_text() } else { app.detail_text() }
	children << ui2.label('', detail, ui2.rect(63, 31, f64(width - 76), 18),
		ui2.TextStyle{
			color: body_muted
			size:  11
		})
	if installed {
		children << ui2.label('', tr('app_selection.installed'), ui2.rect(f64(width - 111), 9, 94, 20),
			ui2.TextStyle{
				color: body_muted
				size:  11
				align: .right
			})
	} else if available {
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
		children << app_selection_bordered('', ui2.rect(f64(width - 41), 9, 22, 22), 5,
			if selected || hovered { app_accent } else { body_rule },
			if selected { app_accent } else { registration_field_bg }, mark)
	}
	mut background := registration_field_bg
	if installed || !available {
		background = app_selection_installed_bg
	} else if selected {
		background = app_selection_selected_bg
	}
	row := app_selection_bordered(app.action, ui2.rect(f64(x), f64(y), f64(width),
		f64(height)), 8, if hovered || selected { app_accent } else { body_rule },
		background, children)
	// The whole row is the hit target, so clicking an app's name or icon picks it.
	return ui2.Element{
		...row
		clickable: !installed && available
		enabled:   !installed && available
	}
}

fn (s &AppSelectionState) element(d &Desktop) ui2.Element {
	mut card_width := 780
	if card_width > d.canvas.width - 24 {
		card_width = d.canvas.width - 24
	}
	if card_width < 1 {
		card_width = 1
	}
	mut card_height := 520
	if card_height > d.canvas.height - 24 {
		card_height = d.canvas.height - 24
	}
	if card_height < 1 {
		card_height = 1
	}
	card_x := (d.canvas.width - card_width) / 2
	card_y := (d.canvas.height - card_height) / 2
	inner := card_width - 48
	sidebar_width := 142
	row_x := sidebar_width + 40
	row_width := card_width - row_x - 24
	available_height := (card_height - 240) / 4
	row_height := if available_height >= app_selection_row_height {
		app_selection_row_height
	} else if available_height >= 48 {
		available_height
	} else {
		48
	}
	row_gap := 6
	category_gap := if card_height >= 488 { 38 } else { 32 }

	mut card_children := frame_elements(24)
	card_children << ui2.label('apps.title', tr('app_selection.heading'), ui2.rect(24, 24, f64(inner),
		34), ui2.TextStyle{
		color: body_heading
		size:  24
		bold:  true
	})
	card_children << ui2.label('apps.subtitle', tr('app_selection.intro'),
		ui2.rect(24, 65, f64(inner), 24), ui2.TextStyle{
			color: body_muted
			size:  12
		})
	for i, category in first_run_categories {
		active := s.category == category
		card_children << ui2.button(first_run_category_actions[i], category.text(),
			ui2.rect(24, f64(app_selection_row_top + i * category_gap), sidebar_width, 32), ui2.BoxStyle{
				bg:     if active { app_selection_selected_bg } else { registration_card }
				radius: 6
			}, ui2.TextStyle{
				color: if active { app_accent } else { body_muted }
				size:  12
				bold:  active
			})
	}
	mut row := 0
	for i, app in first_run_apps {
		if app.category != s.category { continue }
		y := app_selection_row_top + row * (row_height + row_gap)
		row++
		if s.focus == i {
			// The keyboard focus ring thickens the row's border to two pixels.
			card_children << ui2.view('apps.focus', ui2.rect(f64(row_x - 1), f64(y - 1), f64(row_width + 2),
				f64(row_height + 2)), ui2.BoxStyle{
				bg:     app_accent
				radius: 9
			}, []ui2.Element{})
		}
		card_children << app_selection_row(app, s.installed[i], s.available[i], s.selected[i],
			d.hover == app.action, row_x, y, row_width, row_height)
	}
	card_children << ui2.label('apps.note', tr('app_selection.note'),
		ui2.rect(24, f64(card_height - 100), f64(inner), 20), ui2.TextStyle{
			color: body_muted
			size:  11
		})
	mut count := s.selected_count()
	if count >= app_selection_install_labels.len {
		count = app_selection_install_labels.len - 1
	}
	label := app_selection_install_labels[count].text()
	card_children << ui2.button(action_apps_install, label, ui2.rect(24, f64(card_height - 64), f64(inner), 40),
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
			if word == app.package_name && app.package_name !in packages && app.requirement !in [
				.external,
				.steam,
			] {
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
