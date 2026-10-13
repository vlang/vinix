// SPDX-License-Identifier: GPL-2.0-or-later
module main

import encoding.utf8
import tools.packages.pkgadmin
import ui2

fn (mut a SoftwareApp) clear_admin_prompt() {
	for index in 0 .. a.admin_password.len { a.admin_password[index] = 0 }
	a.admin_password_len = 0
	unsafe { a.admin_mask.free() }
	a.admin_mask = []u8{}
	a.admin_prompt = false; a.admin_focus = false; a.admin_select_all = false
}

fn (mut a SoftwareApp) begin_admin_prompt() {
	a.clear_admin_prompt()
	a.admin_mask = []u8{cap: pkgadmin.password_limit}
	unsafe { a.admin_mask.flags |= .noslices }
	a.admin_prompt = true; a.admin_focus = true
	a.focus = false; a.select_all = false
	a.set_status('Enter your own administrator password to approve this package change.')
	fd := a.worker.stdio_fd[0]
	flags := C.fcntl(fd, C.F_GETFL)
	if flags < 0 || C.fcntl(fd, C.F_SETFL, flags | C.O_NONBLOCK) != 0 {
		a.cancel_admin()
		a.set_status('Cannot protect nonblocking administrator password input.')
	}
}

fn (mut a SoftwareApp) cancel_admin() {
	if !a.admin_prompt { return }
	refreshing := a.repository_worker == .refresh
	if a.worker != unsafe { nil } {
		// No credential has been submitted, so the unprivileged client has
		// started no authorized transaction and can be retired immediately.
		a.worker.signal_kill(); a.worker.wait(); a.retire_worker()
	}
	a.clear_admin_prompt()
	if refreshing {
		unsafe { a.repository_result.free() }
		a.repository_result = 'Repository trust was saved; catalog refresh approval was cancelled.'.clone()
		a.read_repositories()
	} else { a.set_status('Administrator approval cancelled before starting the change.') }
}

fn (mut a SoftwareApp) submit_admin() {
	if !a.admin_prompt || a.worker == unsafe { nil } { return }
	if a.admin_password_len == 0 { a.set_status('Enter your administrator password.'); return }
	mut line := [pkgadmin.password_limit + 1]u8{}
	defer { for index in 0 .. line.len { line[index] = 0 } }
	for index in 0 .. a.admin_password_len { line[index] = a.admin_password[index] }
	line[a.admin_password_len] = `\n`
	unsafe { C.signal(C.SIGPIPE, C.SIG_IGN) }
	if C.write(a.worker.stdio_fd[0], &line[0], usize(a.admin_password_len + 1)) != a.admin_password_len + 1 {
		a.set_status('Authentication input is busy or closed. The password was not sent.'); return
	}
	C.close(a.worker.stdio_fd[0]); a.worker.stdio_fd[0] = -1
	a.clear_admin_prompt()
	a.set_status('Authenticating the reviewed package change…')
}

fn (mut a SoftwareApp) handle_admin(event_id string) {
	match event_id {
		'software.admin.password' { a.admin_focus = true }
		'software.admin.approve' { a.submit_admin() }
		'software.admin.cancel' { a.cancel_admin() }
		else {}
	}
}

fn (mut a SoftwareApp) admin_key_input(input string) {
	if !a.admin_focus { return }
	match input {
		'\x1b' { a.cancel_admin() }
		'\r', '\n' { a.submit_admin() }
		'\x01' { a.admin_select_all = true }
		'\x7f', '\x08' {
			old := a.admin_password_len
			mut end := if a.admin_select_all { 0 } else if old > 0 { old - 1 } else { 0 }
			for end > 0 && a.admin_password[end] & 0xc0 == 0x80 { end-- }
			for index in end .. old { a.admin_password[index] = 0 }
			a.admin_password_len = end; a.admin_mask.trim(end); a.admin_select_all = false
		}
		else { a.admin_paste_input(input) }
	}
}

fn (mut a SoftwareApp) admin_paste_input(input string) {
	if !a.admin_prompt || !a.admin_focus { return }
	length := if a.admin_select_all { 0 } else { a.admin_password_len }
	if !utf8.validate_str(input) || input.len > pkgadmin.password_limit - length {
		a.set_status('Password input was kept intact: enter valid UTF-8, at most 256 bytes.'); return
	}
	for byte in input { if byte < 32 || byte == 127 { a.set_status('Password input was kept intact: control characters are not allowed.'); return } }
	if a.admin_select_all {
		for index in 0 .. a.admin_password.len { a.admin_password[index] = 0 }
		a.admin_password_len = 0; a.admin_mask.clear()
	}
	for byte in input {
		a.admin_password[a.admin_password_len] = byte
		a.admin_password_len++; a.admin_mask << `*`
	}
	a.admin_select_all = false
}

fn (mut a SoftwareApp) build_admin(size ui2.Rect) ui2.Element {
	width := int(size.width); height := int(size.height)
	mut children := frame_elements(7)
	if width < 320 || height < 280 {
		children << software_label('Enlarge this window to enter your administrator password.', 14, 8, width - 28, 40, false)
		children << software_button('software.admin.cancel', 'Cancel approval', 14, 54, if width > 28 { width - 28 } else { 1 })
		return ui2.screen(app_surface, children)
	}
	children << software_label('Administrator approval', 14, 8, width - 28, 32, false)
	children << software_label('This package change needs an administrator. Enter your own password; the reviewed operation stays fixed.', 14, 56, width - 28, 68, false)
	mut field := frame_elements(1)
	field << ui2.Element{ ...ui2.text_field('', '', editor_bytes_text(a.admin_mask).clone(), ui2.rect(8, 0, f64(width - 44), 30),
		ui2.BoxStyle{ transparent: true }, ui2.TextStyle{ color: body_text, size: 12 }, 0), key: workflow_owned_text_key }
	children << ui2.clickable_view('software.admin.password', ui2.rect(14, 132, f64(width - 28), 30),
		ui2.BoxStyle{ bg: body_panel, border_color: if a.admin_focus { app_accent } else { body_rule },
			border_top: 1, border_bottom: 1, border_left: 1, border_right: 1 }, field)
	children << software_button('software.admin.approve', 'Approve change', 14, 182, 156)
	children << software_button('software.admin.cancel', 'Cancel', 182, 182, 110)
	children << software_label(a.status, 14, height - 98, width - 28, 90, false)
	return ui2.screen(app_surface, children)
}
