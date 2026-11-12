// SPDX-License-Identifier: GPL-2.0-or-later
module main

import os

// Local pinned-toolchain batch used by the saturating-shift checkpoint. Pass an
// external bundle directory and set VEXE/V_RESOURCE_PATH/V_MACOS_V3_NO_FALLBACK,
// ASAN_OPTIONS=detect_leaks=0:halt_on_error=1 and UBSAN_OPTIONS=halt_on_error=1.

struct Check { name string source string reference bool }
fn main() {
	assert os.args.len == 2
	bundle := os.args[1]
	os.chdir('/Users/alex/code/v')!
	checks := [
		Check{'scalar-asan', 'compat/ios/airbitcode/integer_exec_test.v', false},
		Check{'intrinsic-unit-asan', 'compat/ios/airbitcode/scalar_intrinsics_test.v', false},
		Check{'counts-unit-asan', 'compat/ios/airbitcode/scalar_zero_count_test.v', false},
		Check{'fpclass-unit-asan', 'compat/ios/airbitcode/scalar_fpclass_test.v', false},
		Check{'extrema-unit-asan', 'compat/ios/airbitcode/scalar_integer_extrema_test.v', false},
		Check{'bits-unit-asan', 'compat/ios/airbitcode/scalar_integer_intrinsics_test.v', false},
		Check{'funnel-unit-asan', 'compat/ios/airbitcode/scalar_funnel_test.v', false},
		Check{'fma-unit-asan', 'compat/ios/airbitcode/scalar_fma_test.v', false},
		Check{'abs-unit-asan', 'compat/ios/airbitcode/scalar_integer_abs_test.v', false},
		Check{'abs-asan', 'tests/ios/air-integer-abs.v', true},
		Check{'arith-unit-asan', 'compat/ios/airbitcode/scalar_saturating_test.v', false},
		Check{'counts-asan', 'tests/ios/air-zero-count.v', true},
		Check{'fpclass-asan', 'tests/ios/air-fpclass.v', true},
		Check{'funnel-asan', 'tests/ios/air-funnel.v', true},
		Check{'arith-asan', 'tests/ios/air-saturating.v', true},
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
