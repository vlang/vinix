// SPDX-License-Identifier: GPL-2.0-only
module main

import json2
import os
import stagehost

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
	row := json2.decode[json2.Any](os.get_raw_line()) or {
		eprintln(err)
		exit(1)
	}.as_map()
	result := stagehost.dispatch(row) or {
		failure := if err is stagehost.BindingError {
			err.value
		} else if err is stagehost.StageError {
			{
				'kind':    json2.Any('SystemExit')
				'message': json2.Any(err.msg().bytes().hex())
			}
		} else {
			{
				'kind':    json2.Any('RuntimeError')
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
