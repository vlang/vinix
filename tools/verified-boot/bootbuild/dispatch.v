// SPDX-License-Identifier: GPL-2.0-or-later
module bootbuild

import androidhost as ah

pub fn dispatch(row map[string]ah.Value) !ah.Value {
	args := ah.field(row, 'arguments').items().map(it.text())
	match ah.field(row, 'operation').text() {
		'root_call' { return ah.Value(root_call(args[0], args[1..])!) }
		'command' { command(args[0])! }
		'sign_image' { sign_image(args[0], args[1], args[2], args[3], args[4])! }
		'verify_signature' { verify_signature(args[0], args[1], args[2])! }
		'verify_bundle' { verify_bundle(args[0], args[1], args[2], args[3], args[4])! }
		'build_bundle' { build_bundle(args[0])! }
		'nonnull_next' { return ah.Value(identity_next(args[0], false)!) }
		'none_next' { return ah.Value(identity_next(args[0], true)!) }
		else { return error('Unknown verified-boot bundle operation') }
	}
	return none_value()
}
