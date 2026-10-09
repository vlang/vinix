// SPDX-License-Identifier: GPL-2.0-or-later
module main

import androidhost as ah
import boothost
import gapcore
import json2
import browsercore
import os

fn main() {
	if os.args.len == 3 && os.args[1] == '--install-query' {
		os.cp(os.executable(), os.args[2]) or { panic(err) }
		os.chmod(os.args[2], 0o700) or { panic(err) }
		return
	}
	gapcore.ignore_interrupt()
	row := boothost.unpack(json2.decode[ah.Value](os.get_raw_line()) or { panic(err) }) or { panic(err) }
	value := browsercore.dispatch(row.object()) or {
		failure := if err is gapcore.BindingError {
			err.value
		} else {
			{
				'kind':    ah.Value('RuntimeError')
				'message': ah.Value(err.msg())
			}
		}
		gapcore.finished() or { panic(err) }
		println(ah.encode(boothost.pack(ah.Value({
			'error': ah.Value(failure)
		}))))
		return
	}
	gapcore.finished() or { panic(err) }
	println(ah.encode(boothost.pack(ah.Value({
		'value': value
	}))))
}
