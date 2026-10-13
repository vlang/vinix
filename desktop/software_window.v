// SPDX-License-Identifier: GPL-2.0-or-later
module main

import desktop.packagecore
import tools.packages.appsdk
import ui2

#include <fcntl.h>
#include <unistd.h>
#include <signal.h>

const software_window_action = 'software.window.control.'

fn (mut a SoftwareApp) clear_window() {
	a.window_frame.close()
	unsafe { a.window_pending.free(); a.window_failure.free() }
	a.window_pending = []u8{}
	a.window_failure = ''
	a.window_mode = false; a.window_skip = false; a.window_closing = false; a.window_writable = false
}

fn (mut a SoftwareApp) open_window(request packagecore.Request) ! {
	request.validate()!
	if a.worker != unsafe { nil } || a.terminal_app != unsafe { nil } { return error('a software operation is already running') }
	// App subprocesses and direct Software launches need the same broken-pipe
	// behavior as the compositor: a closed client must return a diagnostic.
	unsafe { C.signal(C.SIGPIPE, C.SIG_IGN) }
	a.clear_window()
	mut arguments := ['run-window', request.id]
	if request.document != '' { arguments << request.document }
	defer { unsafe { (&array(&arguments)).free() } }
	a.start(arguments, false)
	if a.worker == unsafe { nil } { return error('the package service is unavailable') }
	a.worker_run = true
	a.window_mode = true
	a.focus = false; a.select_all = false
	a.window_pending = []u8{cap: appsdk.window_frame_limit + appsdk.window_prefix.len}
	unsafe { a.window_pending.flags |= .noslices }
	fd := a.worker.stdio_fd[0]
	flags := C.fcntl(fd, C.F_GETFL)
	a.window_writable = flags >= 0 && C.fcntl(fd, C.F_SETFL, flags | C.O_NONBLOCK) == 0
	if !a.window_writable {
		// EOF lets a compliant client exit; retain its service/lease until then.
		C.close(fd); a.worker.stdio_fd[0] = -1
		a.set_status('Cannot configure nonblocking application input.')
	} else { a.set_status('Starting native application as the configured ordinary account…') }
}

fn (mut a SoftwareApp) window_line(line string) {
	if !line.starts_with(appsdk.window_prefix) { a.operation_line(line); return }
	// A protocol failure freezes presentation. In particular, do not repeatedly
	// decode malformed publisher input in the privileged desktop process.
	if a.window_failure != '' { return }
	mut frame := appsdk.decode_window_frame(unsafe { tos(line.str + appsdk.window_prefix.len, line.len - appsdk.window_prefix.len) }) or {
		unsafe { a.window_failure.free() }
		a.window_failure = 'Invalid native window response: ' + err.msg()
		a.set_status(a.window_failure)
		unsafe { err.free() }
		return
	}
	if frame.sequence <= a.window_frame.sequence { frame.close(); return }
	a.window_frame.close()
	a.window_frame = frame
	if a.window_failure == '' && !a.window_closing {
		status := 'Application window · ' + frame.title
		a.set_status(status)
		unsafe { status.free() }
	}
}

fn (mut a SoftwareApp) window_output(bytes string) {
	for byte in bytes {
		if byte == `\n` {
			if !a.window_skip && a.window_pending.len > 0 { a.window_line(editor_bytes_text(a.window_pending)) }
			a.window_pending.clear(); a.window_skip = false
		} else if !a.window_skip {
			if a.window_pending.len == appsdk.window_frame_limit + appsdk.window_prefix.len {
				a.window_pending.clear(); a.window_skip = true
				unsafe { a.window_failure.free() }
				a.window_failure = 'Native window response exceeds its size limit.'.clone()
				a.set_status(a.window_failure)
			} else { a.window_pending << byte }
		}
	}
}

fn (mut a SoftwareApp) poll_window() bool {
	if a.worker == unsafe { nil } { return false }
	mut changed := false
	for _ in 0 .. 16 {
		chunk := a.worker.stdout_read()
		if chunk.len == 0 { break }
		changed = true
		a.window_output(chunk)
		unsafe { chunk.free() }
	}
	if a.worker.is_alive() || a.worker.is_pending(.stdout) { return changed }
	code := a.worker.code
	if !a.window_skip && a.window_pending.len > 0 { a.window_line(editor_bytes_text(a.window_pending)) }
	a.window_pending.clear()
	a.retire_worker()
	a.window_writable = false
	tail := software_output_tail(a.output)
	defer { unsafe { tail.free() } }
	if a.window_failure != '' { a.set_status(a.window_failure) }
	else if code != 0 { a.set_status(if tail != '' { tail } else { 'Native application failed.' }) }
	else if a.window_frame.sequence == 0 { a.set_status('The application exited without a native window frame.') }
	else { a.set_status('Application finished. Return to Software when ready.') }
	return true
}

fn (mut a SoftwareApp) send_window_event(event appsdk.WindowEvent) bool {
	if !a.window_writable || a.worker == unsafe { nil } { return false }
	text := event.encode() or { return false }
	line := text + '\n'
	defer { unsafe { text.free(); line.free() } }
	// Smaller than PIPE_BUF, with a nonblocking writer: all or nothing.
	// No package can block the compositor's event loop.
	return C.write(a.worker.stdio_fd[0], line.str, usize(line.len)) == line.len
}

fn (mut a SoftwareApp) request_window_close() {
	if a.window_closing { return }
	if a.send_window_event(appsdk.WindowEvent{ kind: 'close', sequence: a.window_frame.sequence }) {
		a.window_closing = true
		a.set_status('Waiting for the application to close…')
	} else { a.set_status('Application input is busy or closed; try closing again.') }
}

fn (mut a SoftwareApp) handle_window(event_id string) {
	if event_id == 'software.window.back' && a.worker == unsafe { nil } {
		a.clear_window()
		mut arguments := ['view']
		a.start(arguments, true)
		unsafe { (&array(&arguments)).free() }
		return
	}
	if event_id == 'software.window.close' { a.request_window_close(); return }
	if a.window_closing || !event_id.starts_with(software_window_action) { return }
	id := unsafe { tos(event_id.str + software_window_action.len, event_id.len - software_window_action.len) }
	if !a.window_frame.elements.any(it.kind == 'button' && it.id == id) { return }
	if !a.send_window_event(appsdk.WindowEvent{ kind: 'click', sequence: a.window_frame.sequence, id: id }) {
		a.set_status('Application input is busy or closed; the click was not sent.')
	}
}

fn (mut a SoftwareApp) build_window(size ui2.Rect) ui2.Element {
	width := int(size.width)
	height := int(size.height)
	mut children := frame_elements(a.window_frame.elements.len + 4)
	children << software_label('Native application window', 14, 8, width - 202, 28, false)
	children << software_button(if a.worker == unsafe { nil } { 'software.window.back' } else { 'software.window.close' },
		if a.worker == unsafe { nil } { 'Back to Software' } else { 'Close application' }, width - 178, 8, 164)
	frame := a.window_frame
	if frame.sequence > 0 && width > 28 && height > 112 {
		x_scale := f64(width - 28) / f64(frame.width)
		y_scale := f64(height - 112) / f64(frame.height)
		scale := if x_scale < y_scale { x_scale } else { y_scale }
		children << ui2.view('', ui2.rect(14, 48, f64(frame.width) * scale, f64(frame.height) * scale), ui2.BoxStyle{ bg: frame.background }, [])
		for element in frame.elements {
			bounds := ui2.rect(14 + f64(element.x) * scale, 48 + f64(element.y) * scale,
				f64(element.width) * scale, f64(element.height) * scale)
			style := ui2.TextStyle{ color: element.color, size: 14, lines: 3 }
			if element.kind == 'rect' { children << ui2.view('', bounds, ui2.BoxStyle{ bg: element.background }, []) }
			else if element.kind == 'label' {
				children << ui2.Element{ ...ui2.label('', element.text.clone(), bounds, style), key: workflow_owned_text_key }
			} else {
				children << ui2.Element{ ...ui2.button(software_window_action + element.id, element.text.clone(), bounds,
					ui2.BoxStyle{ bg: element.background, radius: 4 }, style), key: workflow_owned_id_text_key }
			}
		}
	}
	children << software_label(a.status, 14, height - 48, width - 28, 44, false)
	return ui2.screen(app_surface, children)
}
