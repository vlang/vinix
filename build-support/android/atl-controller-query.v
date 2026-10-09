module main

import atlcontroller
import androidhost as ah
import boothost
import json2
import os

fn main() {
	if os.args.len == 3 && os.args[1] == '--install-query' {
		os.cp(os.executable(), os.args[2]) or { panic(err) }
		os.chmod(os.args[2], 0o700) or { panic(err) }
		return
	}
	row := boothost.unpack(json2.decode[ah.Value](os.get_raw_line())!)!.object()
	value := atlcontroller.dispatch(row) or {
		println(ah.encode(boothost.pack(ah.Value({'error': ah.Value(boothost.failure(err))}))))
		return
	}
	println(ah.encode(boothost.pack(ah.Value({'value': value}))))
}
