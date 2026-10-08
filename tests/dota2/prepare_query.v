// SPDX-License-Identifier: GPL-2.0-or-later
module main

import hosttest
import json2
import os
import prepcore

fn main() {
	if os.args.len == 3 && os.args[1] == '--install-controller' {
		os.cp(os.executable(), os.args[2]) or {
			eprintln(err)
			exit(1)
		}
		os.chmod(os.args[2], 0o700) or {
			eprintln(err)
			exit(1)
		}
		return
	}
	row := hosttest.decode_json(os.get_raw_line()) or {
		eprintln(err)
		exit(1)
	}.as_map()
	result := prepcore.dispatch(row) or {
		failure := if err is prepcore.BindingError {
			err.value
		} else {
			{
				'kind':    json2.Any(if err is prepcore.PrepareError {
					'SystemExit'
				} else {
					'RuntimeError'
				})
				'message': json2.Any(err.msg().bytes().hex())
			}
		}
		println(json2.encode({
			'error': json2.Any(failure)
		}, escape_unicode: true))
		return
	}
	println(json2.encode({
		'value': result
	}, escape_unicode: true))
}
