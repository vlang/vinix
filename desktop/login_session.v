// SPDX-License-Identifier: GPL-2.0-or-later
module main

import loginchannel

__global desktop_managed_session = false

const action_start_switch_user = 'start.switch_user'

fn (mut d Desktop) switch_login_user() {
	if !desktop_managed_session { return }
	d.close_start_menu()
	// The manager revokes the seat and stops every process in this kernel
	// login. Only a subsequent password check for this account may resume it.
	loginchannel.command(loginchannel.op_switch) or {
		message := err.msg()
		line := 'vinix-desktop: switching users failed: ' + message
		eprintln(line)
		unsafe { line.free(); message.free(); err.free() }
	}
	d.reset_setup_input()
	d.dirty = true
}
