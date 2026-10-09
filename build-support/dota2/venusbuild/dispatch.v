// SPDX-License-Identifier: GPL-2.0-or-later
module venusbuild

import androidhost as ah

pub fn dispatch(row map[string]ah.Value) !ah.Value {
	args := ah.field(row, 'arguments').items().map(it.text())
	match ah.field(row, 'operation').text() {
		'load_lavapipe_builder' { return ah.Value(load_lavapipe_builder()!) }
		'write_cross_file' { return ah.Value(write_cross_file(args[0], args[1], args[2])!) }
		'prepare_source' { prepare_source(args[0], args[1], args[2])! }
		'build' { return ah.Value(build(args[0], args[1], args[2], args[3])!) }
		else { return error('Unknown Venus build operation') }
	}
	return none_value()
}
