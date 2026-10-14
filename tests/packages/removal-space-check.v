// SPDX-License-Identifier: GPL-2.0-or-later
module main

import os

fn invoke(program string, args []string) ! {
	mut process := os.new_process(program)
	process.set_args(args); process.wait(); code := process.code; process.close()
	if code != 0 { return error('removal space qualification failed with status ${code}') }
}

fn check() ! {
	repository := os.dir(os.dir(os.dir(@FILE)))
	v := os.find_abs_path_of_executable(os.getenv_opt('V') or { 'v' })!
	work := os.temp_dir() + '/vinix-removal-space-check-' + os.getpid().str()
	os.mkdir(work)!
	defer { os.rmdir_all(work) or {} }
	header := work + '/statvfs.h'
	os.write_file(header, '#include <sys/statvfs.h>\n#define statvfs(...) vinix_removal_fixture_statvfs(__VA_ARGS__)\n')!
	mut flags := ['-nocache', '-no-skip-unused', '-gc', 'none', '-manualfree', '-d', 'mocked_space',
		'-path', '@vlib|@vmodules|' + repository + '|' + repository + '/tools/accounts', '-cflags', '-include ' + header]
	if '--sanitize' in os.args {
		flags << ['-d', 'no_segfault_handler', '-cc', 'clang', '-cflags', '-fsanitize=address,undefined -fno-omit-frame-pointer',
			'-ldflags', '-fsanitize=address,undefined']
		os.setenv('ASAN_OPTIONS', 'detect_leaks=0', true); os.setenv('UBSAN_OPTIONS', 'halt_on_error=1', true)
	}
	invoke(v, [...flags, '-o', work + '/fixture', repository + '/tests/packages/removal-space-fixture.v'])!
	invoke(work + '/fixture', [])!
}

fn main() { check() or { eprintln(err); exit(1) } }
