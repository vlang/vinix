// SPDX-License-Identifier: GPL-2.0-or-later
module main

import os

// Pinned local checkpoint runner. Pass an external bundle; set VEXE,
// V_RESOURCE_PATH, V_MACOS_V3_NO_FALLBACK, ASAN_OPTIONS and UBSAN_OPTIONS.
struct Check { name string source string reference bool }
fn main() {
	assert os.args.len == 2
	bundle := os.args[1]
	os.chdir('/Users/alex/code/v')!
	checks := [
		Check{'unit-asan', 'compat/ios/airbitcode/scalar_overflow_test.v', false},
		Check{'scalar-asan', 'compat/ios/airbitcode/integer_exec_test.v', false},
		Check{'intrinsic-unit-asan', 'compat/ios/airbitcode/scalar_intrinsics_test.v', false},
		Check{'counts-unit-asan', 'compat/ios/airbitcode/scalar_zero_count_test.v', false},
		Check{'bits-unit-asan', 'compat/ios/airbitcode/scalar_integer_intrinsics_test.v', false},
		Check{'integer-asan', 'tests/ios/air-integer-execute.v', true},
		Check{'flags-asan', 'tests/ios/air-integer-flags.v', true},
		Check{'float-asan', 'tests/ios/air-binary32-execute.v', true},
		Check{'fpclass-asan', 'tests/ios/air-fpclass.v', true},
		Check{'clmul-asan', 'tests/ios/air-clmul.v', true},
		Check{'freeze-asan', 'tests/ios/air-freeze.v', true},
		Check{'reference-asan', 'tests/ios/air-overflow.v', true},
	]
	for check in checks {
		binary := bundle + '/' + check.name
		args := ['-enable-globals', '-nocache', '-gc', 'none', '-cc', 'clang', '-path', '@vlib|/Users/alex/code/vinix/compat/ios|@vmodules', '-cflags', '-O1 -g -fsanitize=address,undefined -fno-omit-frame-pointer', '-ldflags', '-fsanitize=address,undefined', '-o', binary, '/Users/alex/code/vinix/' + check.source]
		mut compiler := os.new_process('/Users/alex/code/v/v')
		compiler.set_args(args); compiler.set_redirect_stdio(); compiler.run(); compiler.wait()
		os.write_file(binary + '-build.log', compiler.stdout_slurp() + compiler.stderr_slurp())!
		code := compiler.code; compiler.close(); assert code == 0, check.name + ' build'
		mut process := os.new_process(binary)
		if check.reference { process.set_args(['self-test', '/opt/homebrew/opt/llvm/bin/llvm-as', bundle + '/llvm-' + check.name]) }
		process.set_redirect_stdio(); process.run(); process.wait()
		output := process.stdout_slurp() + process.stderr_slurp()
		os.write_file(binary + '.log', output)!
		status := process.code; process.close(); assert status == 0, check.name + ' run: ' + output
		println(check.name + ': ' + output)
	}
}
