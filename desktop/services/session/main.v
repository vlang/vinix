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
	mut owner := 0
	for arg in os.args[1..] {
		if arg.starts_with('--session-home=') {
			home = arg['--session-home='.len..]
		} else if arg.starts_with('--session-owner=') {
			owner = int(sessioncore.number(arg['--session-owner='.len..], 0, 2147483647)!)
		} else if arg != '--session-services' {
			eprintln('Usage: vinix-session [--session-home=PATH] [--session-owner=PID]')
			exit(2)
		}
	}
	if !home.starts_with('/') {
		eprintln('session home must be absolute')
		exit(2)
	}
	sessiondaemon.run(home, owner)
}
