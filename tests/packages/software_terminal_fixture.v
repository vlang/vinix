// SPDX-License-Identifier: GPL-2.0-or-later
// Software-only worker fixture; the desktop launcher tests use real TerminalApp.
module main

import desktop.packagecore
import ui2

const terminal_read_chunk = 4096

struct TerminalApp {
mut:
	read_buf []u8
	exited bool
	argv []string
	input string
}

fn (mut a TerminalApp) configure_package(request packagecore.Request, service string) ! {
	request.validate()!
	a.argv = [service.clone(), 'run-terminal'.clone(), request.id.clone()]
	if request.document.len > 0 { a.argv << request.document.clone() }
}

fn (mut a TerminalApp) build(_ ui2.Rect) !ui2.Element { return ui2.screen(u32(0), []) }
fn (mut a TerminalApp) handle(_ string) ! {}
fn (mut a TerminalApp) poll() bool { return false }
fn (mut a TerminalApp) key_input(text string) { unsafe { a.input.free() }; a.input = text.clone() }
fn (mut a TerminalApp) paste_input(text string) { a.key_input(text) }
fn (mut a TerminalApp) close_app() {
	unsafe { a.input.free(); a.read_buf.free(); for arg in a.argv { arg.free() }; (&array(&a.argv)).free() }
}
