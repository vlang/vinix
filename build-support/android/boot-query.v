module main

import androidhost
import boothost
import fixturehost
import json2
import os

fn main() {
	if os.args.len == 3 && os.args[1] == '--install-query' {
		fixturehost.install(os.args[2]) or {
			eprintln(err)
			exit(1)
		}
		return
	}
	line := os.get_raw_line()
	if line == '' { return }
	packed := json2.decode[androidhost.Value](line, strict: true) or { panic(err) }
	row := boothost.unpack(packed) or { panic(err) }
	result := boothost.dispatch(row.object()) or {
		println(androidhost.encode(boothost.pack(androidhost.Value({
			'error': androidhost.Value(boothost.failure(err))
		}))))
		return
	}
	println(androidhost.encode(boothost.pack(androidhost.Value({
		'value': result
	}))))
}
