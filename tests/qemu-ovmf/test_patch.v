// SPDX-License-Identifier: GPL-2.0-only
module main

import os
import ovmffixture
import fixturehost

fn main() {
	if os.args.len == 3 && os.args[1] == '--install-fixture' {
		fixturehost.install(os.args[2]) or { eprintln(err); exit(1) }
		return
	}
	if os.args.len > 2 {
		eprintln('usage: test-patch [CASE]')
		exit(2)
	}
	if os.args.len == 2 && os.args[1] in ['-h', '--help'] {
		println('usage: test-patch [CASE]\n\nExercise firmware patching and setup without downloading or building edk2.')
		return
	}
	if os.find_abs_path_of_executable('git') == none {
		println('SKIP firmware patch tests: git is not installed')
		return
	}
	names := if os.args.len == 2 { [os.args[1].all_after_last('.')] } else { ovmffixture.case_names }
	for name in names {
		ovmffixture.run_case(name) or { eprintln(err); exit(1) }
		if os.args.len == 1 { println('PASS ' + name) }
	}
}
