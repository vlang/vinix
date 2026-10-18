// SPDX-License-Identifier: GPL-2.0-or-later
module main

import desktop.sessiondaemon
import desktop.sessioncore
import desktop.sessionipc
import os

fn main() {
	if os.args.len >= 3 && os.args[1] == '--session-control' {
		reply := sessionipc.session_call(os.args[2], os.args[3..]) or {
			eprintln(err)
			exit(1)
		}
		println(reply)
		unsafe { reply.free() }
		return
	}
	mut home := '/root'
	mut control := -1
	for arg in os.args[1..] {
		if arg.starts_with('--session-home=') {
			home = arg['--session-home='.len..]
		} else if arg.starts_with('--session-control-fd=') {
			control = int(sessioncore.number(arg['--session-control-fd='.len..], 3, 2147483647)!)
		} else if arg != '--session-services' {
			eprintln('Usage: vinix-session [--session-home=PATH] --session-control-fd=FD')
			exit(2)
		}
	}
	if !home.starts_with('/') {
		eprintln('session home must be absolute')
		exit(2)
	}
	if sessionipc.session_control_peer(control) == none {
		eprintln('vinix-session: an inherited compositor connection is required')
		exit(2)
	}
	sessiondaemon.run(home, control)
}
