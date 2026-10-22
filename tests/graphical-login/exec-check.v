// SPDX-License-Identifier: GPL-2.0-or-later
// Execute the production exec boundary, including registration, in real children.
module main

import os

fn between(source string, first string, next string) !string {
	start := source.index(first) or { return error('missing source marker: ' + first) }
	end := source.index_after(next, start + first.len) or { return error('missing source marker: ' + next) }
	return source[start..end]
}

fn check() ! {
	root := os.real_path(os.dir(@FILE) + '/../..')
	work := os.temp_dir() + '/vinix-compositor-exec-' + os.getpid().str()
	os.mkdir_all(work)!
	defer { os.rmdir_all(work) or {} }
	become := os.read_file(root + '/tools/accounts/sessioncore/become.v')!
	launch := os.read_file(root + '/tools/accounts/sessioncore/launch.v')!
	graphical := os.read_file(root + '/tools/accounts/sessioncore/graphical.v')!
	mut code := os.read_file(root + '/tests/graphical-login/exec-fixture.v.txt')!
	code += between(become, 'pub fn exec_as(', '// One write()')!
	code += between(launch, 'fn inherited_environment()', '// The child writes')!
	code += launch.all_after('// Wait for a process and return its exit status the way a shell would.')
	code += between(graphical, 'fn run_setup(', 'fn has_person(')!
	negative := '--negative-no-fallback' in os.args
	if negative {
		code = code.replace('if fallback.len > 0 {', 'if false && fallback.len > 0 {')
	}
	os.write_file(work + '/main.v', code)!
	v := os.getenv('VEXE')
	if v == '' { return error('set VEXE to the qualified V compiler') }
	mut compiler_args := ['-w', '-cc', 'clang', '-nocache', '-enable-globals', '-gc', 'none', '-manualfree',
		'-path', '@vlib|' + root + '/tools/accounts|@vmodules', '-o', work + '/check']
	if '--sanitize' in os.args {
		compiler_args << ['-cflags', '-fsanitize=address,undefined', '-ldflags', '-fsanitize=address,undefined']
	}
	compiler_args << work + '/main.v'
	mut compiler := os.new_process(v)
	defer { compiler.close() }
	compiler.set_args(compiler_args)
	compiler.wait()
	if compiler.code != 0 { return error('exec regression did not compile') }
	mut child := os.new_process(work + '/check')
	defer { child.close() }
	child.wait()
	if negative {
		if child.code == 0 { return error('disabled fallback unexpectedly passed') }
		println('PASS compositor exec negative control: disabled recovery refused')
	} else if child.code != 0 { return error('exec regression failed') }
}

fn main() {
	check() or { eprintln(err); exit(1) }
}
