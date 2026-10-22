// SPDX-License-Identifier: GPL-2.0-or-later
module main

import math
import ui2

const first_run_release_decision_name = '.vinix-first-run-release'
const action_first_run_release_review = 'apps.release.review'
const action_first_run_release_skip = 'apps.release.skip'

enum FirstRunAppsAction {
	none
	install_legacy
	review_release
}

enum FirstRunReleaseChoice {
	pending
	review
	skip
}

struct FirstRunReleaseState {
mut:
	choice FirstRunReleaseChoice
	focus int
	save_failed bool
}

fn first_run_release_available(path string) bool {
	mut info := C.stat{}
	return C.lstat(path.str, unsafe { &info }) == 0 && info.st_mode & 0o170000 == 0o100000
}

fn first_run_release_decided(home string) bool {
	path := '${home}/${first_run_release_decision_name}'
	defer { unsafe { path.free() } }
	fd := C.open(path.str, C.O_RDONLY | C.O_NOFOLLOW | C.O_CLOEXEC | C.O_NONBLOCK)
	if fd < 0 { return false }
	defer { C.close(fd) }
	mut info := C.stat{}
	if C.fstat(fd, unsafe { &info }) != 0 || info.st_mode & 0o170000 != 0o100000
		|| info.st_size < 5 || info.st_size > 7 { return false }
	mut bytes := [8]u8{}
	count := C.read(fd, &bytes[0], usize(bytes.len))
	return (count == 5 && bytes[0] == `s` && bytes[1] == `k` && bytes[2] == `i`
		&& bytes[3] == `p` && bytes[4] == `\n`)
		|| (count == 7 && bytes[0] == `r` && bytes[1] == `e` && bytes[2] == `v`
			&& bytes[3] == `i` && bytes[4] == `e` && bytes[5] == `w` && bytes[6] == `\n`)
}

// Native account setup bypasses legacy registration. Its first release choice
// is therefore independent of the old pending marker, and survives Skip/reboot.
fn first_run_release_pending(home string, uid u32, declaration string) bool {
	return first_run_release_available(declaration) && !first_run_release_decided(home)
		&& (uid != 0 || desktop_app_selection_pending(home))
}

fn first_run_release_save(home string, choice FirstRunReleaseChoice) bool {
	if choice == .pending { return false }
	path := '${home}/${first_run_release_decision_name}'
	temporary := path + '.new.XXXXXX'
	defer { unsafe { path.free(); temporary.free() } }
	// The existing calendar marker helper uses mkstemp too: exclusively create
	// a private 0600 sibling without following links. Crash leftovers cannot
	// block future choices because each attempt gets a fresh random name.
	fd := int(C.mkstemp(temporary.str))
	if fd < 0 { return false }
	if !desktop_set_cloexec(fd, true) { C.close(fd); C.unlink(temporary.str); return false }
	// Persist the explicit choice before handing off. Software's normal release
	// review remains available if a crash or failed window launch loses delivery.
	data := if choice == .review { 'review\n' } else { 'skip\n' }
	written := C.write(fd, data.str, usize(data.len))
	closed := C.close(fd)
	if written != data.len || closed != 0 {
		C.unlink(temporary.str)
		return false
	}
	if C.rename(temporary.str, path.str) != 0 { C.unlink(temporary.str); return false }
	$if vinix { C.sync() }
	if desktop_app_selection_pending(home) { desktop_finish_app_selection(home) }
	return true
}

fn (mut s FirstRunReleaseState) handle_action(action string, home string) {
	if s.choice != .pending { return }
	choice := match action {
		action_first_run_release_review { FirstRunReleaseChoice.review }
		action_first_run_release_skip { FirstRunReleaseChoice.skip }
		else { return }
	}
	s.focus = if choice == .review { 0 } else { 1 }
	if !first_run_release_save(home, choice) { s.save_failed = true; return }
	s.choice = choice
}

fn (mut s FirstRunReleaseState) key_input(input string, home string) {
	mut index := 0
	for index < input.len && s.choice == .pending {
		if input[index] == 27 {
			if index + 2 < input.len && input[index + 1] == `[` {
				if input[index + 2] in [`Z`, `A`, `B`, `C`, `D`] { s.focus = 1 - s.focus }
				index += 3
				continue
			}
			s.handle_action(action_first_run_release_skip, home)
			return
		}
		match input[index] {
			9 { s.focus = 1 - s.focus }
			`\r`, `\n`, ` ` { s.handle_action(if s.focus == 0 { action_first_run_release_review } else { action_first_run_release_skip }, home) }
			else {}
		}
		index++
	}
}

fn (s &FirstRunReleaseState) element(d &Desktop) ui2.Element {
	width := math.max(1, math.min(680, d.canvas.width - 24))
	height := math.max(1, math.min(330, d.canvas.height - 24))
	compact := height < 300 || width < 600
	padding := if compact { 16 } else { 24 }
	inner := math.max(1, width - 2 * padding)
	button_height := if compact { 28 } else { 40 }
	button_gap := if compact { 8 } else { 12 }
	skip_y := height - padding - button_height - if compact { 0 } else { 14 }
	review_y := skip_y - button_gap - button_height
	mut children := frame_elements(24)
	children << ui2.label('apps.release.title', tr('app_selection.release.heading'), ui2.rect(f64(padding), if compact { 8 } else { 24 }, f64(inner), 34), ui2.TextStyle{ color: body_heading, size: if compact { 18 } else { 24 }, bold: true })
	mut body_y := if compact { 40 } else { 76 }
	for index, text in [tr('app_selection.release.intro'), tr('app_selection.release.removals'), tr('app_selection.release.confirm')]! {
		if compact {
			message := if index == 0 && s.save_failed { tr('app_selection.release.save_failed') } else { text }
			body_y = first_run_release_paragraph(mut children, d, message, padding, body_y, inner,
				if index == 0 && s.save_failed { registration_error } else { body_text })
		} else {
			children << ui2.label('', text, ui2.rect(f64(padding), f64(76 + index * 26), f64(inner), 24), ui2.TextStyle{ color: body_text, size: 12 })
		}
	}
	if s.save_failed && !compact {
		children << ui2.label('apps.release.error', tr('app_selection.release.save_failed'), ui2.rect(f64(padding), 158, f64(inner), 18), ui2.TextStyle{ color: registration_error, size: 11 })
	}
	for index, action in [action_first_run_release_review, action_first_run_release_skip]! {
		children << ui2.button(action, if index == 0 { tr('app_selection.release.review') } else { tr('app_selection.release.skip') },
			ui2.rect(f64(padding), f64(if index == 0 { review_y } else { skip_y }), f64(inner), f64(button_height)), ui2.BoxStyle{
				bg: if index == 0 { app_accent } else { registration_field_bg }
				radius: 6
				border_color: if s.focus == index { body_heading } else { body_rule }
				border_left: 2, border_top: 2, border_right: 2, border_bottom: 2
			}, ui2.TextStyle{ color: if index == 0 { app_on_accent } else { body_text }, size: 13, bold: true, align: .center })
	}
	card := ui2.view('apps.release.window', ui2.rect(f64((d.canvas.width - width) / 2), f64((d.canvas.height - height) / 2), f64(width), f64(height)),
		ui2.BoxStyle{ bg: registration_card, radius: 12 }, children)
	return ui2.screen(registration_backdrop, frame_child(card))
}

// Borrow complete UTF-8 runs from process-lifetime translations. The compact
// card wraps explanatory text instead of silently truncating its warnings.
fn first_run_release_paragraph(mut children []ui2.Element, d &Desktop, text string,
	x int, y int, width int, color u32) int {
	style := ui2.TextStyle{ color: color, size: 11 }
	face := d.face_for(style)
	mut at := 0
	mut line_y := y
	for at < text.len {
		start := at
		mut end := at
		mut space := -1
		mut pixels := 0
		for end < text.len {
			r, size := next_rune(text, end)
			advance := face.glyph_for(r).advance / face.raster_scale
			if end > start && pixels + advance > width { break }
			if r == ` ` { space = end }
			pixels += advance
			end += size
		}
		if end < text.len && space > start { end = space }
		line := unsafe { tos(text.str + start, end - start) }
		children << ui2.label('', line, ui2.rect(f64(x), f64(line_y), f64(width), f64(face.line_height)), style)
		at = end
		for at < text.len && text[at] == ` ` { at++ }
		line_y += face.line_height
	}
	return line_y
}

fn (mut d Desktop) choose_first_run_release(mut fb Framebuffer, mut pointer PointerDevice,
	mut keyboard Keyboard, frame_interval i64, idle_interval i64) FirstRunAppsAction {
	mut state := FirstRunReleaseState{}
	mut dirty := true
	for state.choice == .pending {
		if !dirty { desktop_wait_for_input(pointer.fd, keyboard.fd, idle_interval) }
		power := desktop_pending_power_action()
		if power == .reload_desktop { d.end_session(power); return .none }
		if power != .keep_running { desktop_power_apply(power) }
		if packet := pointer.poll() {
			dirty = true
			if packet.max_x > 0 && packet.max_y > 0 {
				d.pointer_present = true
				d.pointer_x = int(i64(packet.x) * i64(d.canvas.width - 1) / i64(packet.max_x))
				d.pointer_y = int(i64(packet.y) * i64(d.canvas.height - 1) / i64(packet.max_y))
				d.buttons = packet.buttons
				d.set_hover(d.hit_action(d.pointer_x, d.pointer_y))
				if packet.pressed & button_left != 0 { state.handle_action(d.hover, desktop_home) }
			} else { d.pointer_present = false }
		}
		keys := keyboard.poll_text()
		if keys.len > 0 { state.key_input(keys, desktop_home); dirty = true }
		if state.choice != .pending || !dirty { continue }
		frame_started := monotonic_millis()
		begin_frame_elements()
		tree := state.element(d)
		d.render(tree)
		fb.present(&d.canvas, desktop_current_scale())
		free_tree(tree)
		dirty = false
		sleep_to_next_frame(frame_started, frame_interval)
	}
	d.reset_setup_input()
	return if state.choice == .review { .review_release } else { .none }
}

fn (mut d Desktop) open_first_run_release_review() {
	before := d.next_id
	d.launch_titled_at_startup('Software')
	if d.next_id > before { d.send_to_window(d.next_id - 1, software_first_run_release_action) }
}
