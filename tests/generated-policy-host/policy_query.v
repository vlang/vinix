// SPDX-License-Identifier: GPL-2.0-only
module main
import fixturehost
import hosttest
import json2
import os
import policyhost

fn main() {
	if os.args.len == 3 && os.args[1] == '--install-controller' {
		fixturehost.install(os.args[2]) or { eprintln(err); exit(1) }; return
	}
	row := hosttest.decode_json(os.get_raw_line()) or { eprintln(err); exit(1) }.as_map()
	result := policyhost.dispatch(row) or {
		failure := if err is policyhost.BindingError { err.value } else if err is policyhost.PolicyError {
			{'kind': json2.Any(err.kind), 'message': json2.Any(err.message.bytes().hex())}
		} else { {'kind': json2.Any('RuntimeError'), 'message': json2.Any(err.msg().bytes().hex())} }
		println(json2.encode({'error': json2.Any(failure)}, escape_unicode: true)); return
	}
	println(json2.encode({'value': result}, escape_unicode: true))
}
