// SPDX-License-Identifier: GPL-2.0-or-later
module main

import desktop.packagecore
import ui2

fn (mut a SoftwareApp) open_terminal_request(request packagecore.Request) ! {
	request.validate()!
	if a.worker != unsafe { nil } || a.terminal_app != unsafe { nil } { return error('a software operation is already running') }
	mut terminal := &TerminalApp{ read_buf: []u8{len: terminal_read_chunk} }
	terminal.configure_package(request, a.service_path) or {
		terminal.close_app()
		unsafe { free(terminal) }
		return err
	}
	a.clear_review()
	a.clear_repository_review()
	a.terminal_app = terminal
	a.set_status('The application runs as the configured ordinary account. Exit it to return to Software.')
}

fn (mut a SoftwareApp) close_terminal() {
	if a.terminal_app == unsafe { nil } { return }
	a.terminal_app.close_app()
	unsafe { free(a.terminal_app) }
	a.terminal_app = unsafe { nil }
}

fn (mut a SoftwareApp) build_terminal(size ui2.Rect) !ui2.Element {
	width := int(size.width)
	height := int(size.height)
	view := a.terminal_app.build(ui2.rect(0, 0, f64(width), f64(if height > 96 { height - 96 } else { 1 })))!
	mut children := frame_elements(4)
	children << software_label('Application Terminal', 14, 8, width - 202, 28, false)
	if a.terminal_app.exited { children << software_button('software.terminal-back', 'Back to Software', width - 178, 8, 164) }
	children << ui2.Element{ ...view, frame: ui2.rect(0, 44, f64(width), f64(if height > 96 { height - 96 } else { 1 })) }
	children << software_label(a.status, 14, height - 48, width - 28, 44, false)
	return ui2.screen(app_surface, children)
}
