// SPDX-License-Identifier: GPL-2.0-or-later
// Test-only compiler delegate: real compilation with controlled output/failures.
module main

import hosttest
import os

fn main() {
	mode := os.getenv('VINIX_BOUNDARY_CASE')
	if mode == 'compile-failure' {
		eprintln('forced compiler failure')
		exit(37)
	}
	for path in os.args[1..] {
		if path.ends_with('/v/lib.c') && mode == 'allocator' {
			text := os.read_file(path)!
			os.write_file(path, text + '\nextern void* malloc(unsigned long);\nvoid* boundary_allocator_fixture(unsigned long n) { return malloc(n); }\n')!
		}
		if path.ends_with('/v/fixture.c') && mode in ['mismatch', 'fixture-failure'] {
			mut text := os.read_file(path)!
			if mode == 'mismatch' {
				assert text.contains('NATIVE HEADER BOUNDARIES: PASS')
				text = text.replace('NATIVE HEADER BOUNDARIES: PASS', 'FORCED OUTPUT DIFFERENCE')
			} else {
				text += '\nextern void _Exit(int);\n__attribute__((constructor)) static void boundary_failure_fixture(void) { _Exit(43); }\n'
			}
			os.write_file(path, text)!
		}
	}
	mut argv := [os.getenv('VINIX_BOUNDARY_REAL_CC')]
	argv << os.args[1..]
	result := hosttest.capture(argv, '', 90, os.environ())!
	print(result.stdout)
	eprint(result.stderr)
	exit(result.code)
}
