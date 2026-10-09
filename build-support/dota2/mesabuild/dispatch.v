// SPDX-License-Identifier: GPL-2.0-or-later
module mesabuild

import androidhost as ah

pub fn dispatch(row map[string]ah.Value) !ah.Value {
	args := ah.field(row, 'arguments').items().map(it.text())
	match ah.field(row, 'operation').text() {
		'digest' { return ah.Value(digest(args[0])!) }
		'tool' { return ah.Value(tool(args[0])!) }
		'load_resolver' { return ah.Value(load_resolver()!) }
		'load_inputs' { return ah.Value(load_inputs(args[0])!) }
		'llvm_bin' { return ah.Value(llvm_bin()!) }
		'base_identity' { return ah.Value(base_identity(args[0])!) }
		'logged' { logged(args[0], args[1], args[2], args[3])! }
		'apply_patch' { apply_patch(args[0], args[1], args[2])! }
		'check_sources' { check_sources(args[0], args[1], args[2])! }
		'prepare_source' { prepare_source(args[0], args[1], args[2], args[3])! }
		'prepare_sysroot' { prepare_sysroot(args[0], args[1], args[2], args[3], args[4])! }
		'write_configuration' { return ah.Value(write_configuration(args[0], args[1], args[2])!) }
		'verify_library' { verify_library(args[0], args[1], args[2])! }
		'build' { return ah.Value(build(args[0], args[1], args[2], args[3])!) }
		else { return error('Unknown Mesa build operation') }
	}
	return none_value()
}
