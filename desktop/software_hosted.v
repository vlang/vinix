// SPDX-License-Identifier: GPL-2.0-or-later
module main

import desktop.packagecore
import desktop.sessioncore
import ui2

fn (mut a SoftwareApp) open_hosted_package(request packagecore.Request) ! {
	request.validate()!
	if C.geteuid() == 0 { return error('Open graphical packages from an ordinary account session.') }
	if a.service_path != '/usr/bin/vinix-package' { return error('Graphical packages require the signed package launcher.') }
	if a.worker != unsafe { nil } || a.hosted_app != unsafe { nil } || a.terminal_app != unsafe { nil } || a.window_mode {
		return error('a software operation is already running')
	}
	mut arguments := ['run', request.id.clone()]
	if request.document != '' { arguments << request.document.clone() }
	defer { unsafe { arguments.free() } }
	// The actual signed launcher verifies publisher, payload, runtime, policy
	// and data ownership, then retains its generation lease around the child.
	a.hosted_app = open_hosted_x11_command('package', a.service_path, arguments, true, 1024, 768,
		'builtin:software', .package_starting, .package_missing, .package_exited)
}

fn (mut a SoftwareApp) close_hosted_package() {
	if a.hosted_app == unsafe { nil } { return }
	a.hosted_app.close_app()
	if a.hosted_app.damage_counter != unsafe { nil } {
		desktop_munmap(a.hosted_app.damage_counter, sizeof(u32))
	}
	unsafe {
		a.hosted_app.directory.free()
		a.hosted_app.xwd_path.free()
		a.hosted_app.damage_path.free()
		a.hosted_app.image_path.free()
		free(a.hosted_app)
	}
	a.hosted_app = unsafe { nil }
}

fn (mut a SoftwareApp) build_hosted_package(size ui2.Rect) !ui2.Element {
	if !a.hosted_app.failed { return a.hosted_app.build(size) }
	view := a.hosted_app.build(size)!
	mut children := frame_elements(2)
	children << view
	children << software_button('software.hosted-back', tr('wine.package.back'), 14, 10, 180)
	return ui2.screen(app_surface, children)
}

fn (mut a SoftwareApp) pointer_input_enabled() bool {
	return a.hosted_app != unsafe { nil } && a.hosted_app.pointer_input_enabled()
}

fn (mut a SoftwareApp) pointer_event(phase AppPointerPhase, button AppPointerButton, scroll int, x int, y int, width int, height int) {
	if a.hosted_app != unsafe { nil } { a.hosted_app.pointer_event(phase, button, scroll, x, y, width, height) }
}

fn (mut a SoftwareApp) take_clipboard_copy_request() []u8 {
	return if a.hosted_app != unsafe { nil } { a.hosted_app.take_clipboard_copy_request() } else { []u8{} }
}

fn (mut a SoftwareApp) receive_clipboard_copy_reply(text string) {
	if a.hosted_app != unsafe { nil } { a.hosted_app.receive_clipboard_copy_reply(text) }
}

fn (mut a SoftwareApp) paste_data(kind sessioncore.DataKind, text string) {
	if a.hosted_app != unsafe { nil } { a.hosted_app.paste_data(kind, text) } else if kind == .text { a.paste_input(text) }
}
