// SPDX-License-Identifier: GPL-2.0-or-later
module muslstage

import androidhost as ah

pub fn dispatch(row map[string]ah.Value) !ah.Value {
	args := ah.field(row, 'arguments').items().map(it.text())
	match ah.field(row, 'operation').text() {
		'plan' {
			return ah.Value(plan(args[0], args[1], args[2], args[3], args[4], args[5], args[6])!)
		}
		'sha256' { return ah.Value(sha256(args[0])!) }
		'install' { install(args[0], args[1], args[2])! }
		'replace_link' { replace_link(args[0], args[1])! }
		else { return error('Unknown musl staging operation') }
	}
	return none_value()
}
