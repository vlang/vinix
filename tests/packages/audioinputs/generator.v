// SPDX-License-Identifier: GPL-2.0-or-later
module audioinputs

import os

// The compatibility entry point imports these modules by their short names.
// Supply their captured checkout parents instead of relying on global modules
// or an ancestor checkout when VMODULES is private and empty.
pub fn sandbox_generator_arguments(root string, v string, host_cc string, binary string) ![]string {
	for path in [root, v, host_cc, binary] {
		if !os.is_abs_path(path) || path.bytes().any(it < 32 || it == 127)
			|| path.contains('|') { return error('generator paths must be absolute and representable in V module paths') }
	}
	paths := ['@vlib', '@vmodules', root, root + '/build-support/native-compat-tools',
		root + '/tests/qemu-core', root + '/tests/linuxkpi', root + '/tests/native-guest-tools',
		root + '/tests/host-policy', root + '/tests/native-policy-tools']
	return [v, '-prod', '-nocache', '-keepc', '-backend', 'c', '-cc', host_cc, '-path', paths.join('|'),
		'-o', binary, root + '/build-support/native-compat-tools/main.v']
}

// A host helper must not consume a target compiler's include or linker flags.
// Empty per-process overrides leave the controller's environment unchanged.
pub fn sandbox_generator_environment() map[string]string {
	return {'CFLAGS': '', 'CPPFLAGS': '', 'LDFLAGS': ''}
}
