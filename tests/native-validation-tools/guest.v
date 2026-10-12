// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module main

import cachecli
import guestvalidation
import os

fn main() {
	guard := cachecli.own_commands()
	defer { guard.close() }
	name := os.executable().all_after_last('/')
	mut command := name
	mut arguments := os.args[1..]
	if name == 'validation-guest' {
		if arguments.len == 0 {
			eprintln('expected guest validation command')
			exit(2)
		}
		command = arguments[0]
		arguments = arguments[1..]
	}
	status := dispatch_guest(command, arguments) or {
		eprintln(err)
		exit(if cachecli.cancelled() {
			cachecli.interrupt_status()
		} else if err.code() == 2 {
			2
		} else {
			1
		})
	}
	exit(if cachecli.cancelled() { cachecli.interrupt_status() } else { status })
}

fn dispatch_guest(command string, arguments []string) !int {
	return match command {
		'qemu-dns' { guestvalidation.dns_cli(arguments)! }
		'x-window-check' { guestvalidation.xwindow_cli(arguments)! }
		'codex-smoke', 'claude-smoke' {
			guestvalidation.smoke_cli('', arguments, command == 'claude-smoke')!
		}
		else { return error_with_code('unknown guest validation command: ' + command, 2) }
	}
}
