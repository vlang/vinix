module main

import androidhost as ah
import boothost
import json2
import os
import runhost

fn main() {
	if os.args.len == 3 && os.args[1] == '--install-query' {
		os.cp(os.executable(), os.args[2]) or { panic(err) }
		os.chmod(os.args[2], 0o700) or { panic(err) }
		return
	}
	row := boothost.unpack(json2.decode[ah.Value](os.get_raw_line()) or { panic(err) }) or { panic(err) }
	result := runhost.dispatch(row.object()) or {
		failure := if err is runhost.BindingError { err.value } else if err is runhost.PolicyError {
			{'kind': ah.Value(err.kind), 'message': ah.Value(err.message)}
		} else { (json2.decode[ah.Value](ah.error_json(err)) or { panic(err) }).object() }
		println(ah.encode(boothost.pack(ah.Value({'error': ah.Value(failure)}))))
		return
	}
	println(ah.encode(boothost.pack(ah.Value({'value': result}))))
}
