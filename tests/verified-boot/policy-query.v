// SPDX-License-Identifier: GPL-2.0-or-later
module main

import androidhost as ah
import boothost
import boottest
import json2
import os
import packagestore

#include <signal.h>

fn C.signal(i32, voidptr) voidptr

fn main() {
	if os.args.len == 3 && os.args[1] == '--install-query' {
		os.cp(os.executable(), os.args[2]) or { panic(err) }
		os.chmod(os.args[2], 0o700) or { panic(err) }
		return
	}
	previous := unsafe { C.signal(C.SIGINT, C.SIG_IGN) }
	defer { unsafe { C.signal(C.SIGINT, previous) } }
	row := boothost.unpack(json2.decode[ah.Value](os.get_raw_line()) or { panic(err) }) or { panic(err) }
	result := boottest.dispatch(row.object()) or {
		failure := if err is packagestore.BindingError {
			err.value
		} else {
			{
				'kind':    ah.Value('RuntimeError')
				'message': ah.Value(err.msg())
			}
		}
		println(ah.encode(boothost.pack(ah.Value({
			'error': ah.Value(failure)
		}))))
		return
	}
	println(ah.encode(boothost.pack(ah.Value({
		'value': result
	}))))
}
