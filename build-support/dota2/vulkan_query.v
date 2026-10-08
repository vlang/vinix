// SPDX-License-Identifier: GPL-2.0-or-later
module main

import fixturehost
import hosttest
import json2
import os
import vulkanbuild

#include <signal.h>

fn C.signal(i32, voidptr) voidptr

fn main() {
	if os.args.len == 3 && os.args[1] == '--install-query' {
		fixturehost.install(os.args[2]) or {
			eprintln(err)
			exit(1)
		}
		return
	}
	// Python retains Ctrl-C and its original exception; the callback controller
	// stays alive long enough to return that exception and retire its owner.
	previous := unsafe { C.signal(C.SIGINT, C.SIG_IGN) }
	defer { unsafe { C.signal(C.SIGINT, previous) } }
	row := hosttest.decode_json(os.get_raw_line()) or {
		eprintln(err)
		exit(1)
	}.as_map()
	value := vulkanbuild.dispatch(row) or {
		println(json2.encode({
			'error': json2.Any(vulkanbuild.failure_record(err))
		}, escape_unicode: true))
		return
	}
	println(json2.encode({
		'value': value
	}, escape_unicode: true))
}
