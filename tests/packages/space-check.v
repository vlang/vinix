// SPDX-License-Identifier: GPL-2.0-or-later
module main

import os

fn invoke(arguments []string) ! {
	mut process := os.new_process(arguments[0])
	defer { process.close() }
	process.set_args(arguments[1..])
	process.wait()
	if process.code != 0 { return error('package space fixture failed with status ${process.code}') }
}

fn check() ! {
	repository := os.dir(os.dir(os.dir(@FILE)))
	v := os.find_abs_path_of_executable(os.getenv_opt('V') or { 'v' })!
	parent := os.getenv_opt('VINIX_PACKAGE_SPACE_WORK') or { os.temp_dir() }
	work := parent + '/vinix-space-' + os.getpid().str()
	os.mkdir_all(work)!
	defer { os.rmdir_all(work) or {} }
	header := work + '/statvfs-fixture.h'
	// Include guards keep later production includes from changing the ABI. A
	// function-like macro leaves uses of `struct statvfs` untouched.
	os.write_file(header, '#include <sys/statvfs.h>\n#define statvfs(...) vinix_package_fixture_statvfs(__VA_ARGS__)\n')!
	mut flags := ['-nocache', '-no-skip-unused', '-gc', 'none', '-manualfree',
		'-path', '@vlib|@vmodules|' + repository + '|' + repository + '/tools/accounts',
		'-cflags', '-include ' + header]
	if '--sanitize' in os.args {
		flags << ['-d', 'no_segfault_handler', '-cc', 'clang', '-cflags',
			'-fsanitize=address,undefined -fno-omit-frame-pointer', '-ldflags', '-fsanitize=address,undefined']
		os.setenv('ASAN_OPTIONS', 'detect_leaks=0', true)
		os.setenv('UBSAN_OPTIONS', 'halt_on_error=1', true)
	}
	invoke([v, ...flags, '-o', work + '/space-fixture', repository + '/tests/packages/space-fixture.v'])!
	invoke([work + '/space-fixture'])!
}

fn main() { check() or { eprintln(err); exit(1) } }
