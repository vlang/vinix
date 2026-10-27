// SPDX-License-Identifier: GPL-2.0-or-later
module frozenv

import os

// Older captured toolchains omitted v.mod. Without that marker, @VEXEROOT
// directives can resolve relative to builtin instead of the captured library.
pub fn configure(mut process os.Process, executable string) ! {
	if !executable.ends_with('/toolchain/v') { return }
	root := os.dir(executable)
	if !os.exists(root + '/v.mod') {
		os.write_file(root + '/v.mod', "Module {\n\tname: 'V'\n\tdescription: 'Frozen V compiler library root'\n\tversion: '0.5.2'\n}\n")!
	}
	process.set_work_folder(root)
}
