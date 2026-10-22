// SPDX-License-Identifier: GPL-2.0-or-later
// Execute the actual manager preparation and attendance functions with a
// controlled launcher, retaining the real fork/socketpair secret lifetime.
module main

import os

fn between(source string, first string, next string) !string {
	start := source.index(first) or { return error('missing source marker: ' + first) }
	end := source.index_after(next, start + first.len) or { return error('missing source marker: ' + next) }
	return source[start..end]
}

fn check() ! {
	root := os.real_path(os.dir(@FILE) + '/../..')
	work := os.temp_dir() + '/vinix-manager-secret-' + os.getpid().str()
	os.mkdir_all(work)!
	defer { os.rmdir_all(work) or {} }
	manager := os.read_file(root + '/tools/accounts/sessioncore/manager.v')!
	mut code := os.read_file(root + '/tests/graphical-login/secret-fixture.v.txt')!
	code += between(manager, 'pub struct ManagerConfig', 'fn load_accounts()')!
	code += between(manager, 'fn (mut m Manager) find_session(', '// Check a name')!
	code += between(manager, 'fn login_field_text(', 'fn mark_active_uid(')!
	code += between(manager, 'fn (mut m Manager) prepare_session(', '// A signal interrupts')!
	secret := os.read_file(root + '/tools/accounts/sessioncore/secret.c.v')!
	code += secret.all_after('module sessioncore')
	negative_reap := '--negative-reap' in os.args
	if negative_reap {
		if !code.contains('\twait(session.pid)\n') {
			return error('missing production retirement boundary')
		}
		code = code.replace('\twait(session.pid)\n', '\tmut reap_status := i32(0)\n\tC.waitpid(session.pid, &reap_status, C.WNOHANG)\n')
	}
	os.write_file(work + '/main.v', code)!
	v := os.getenv('VEXE')
	if v == '' { return error('set VEXE to the qualified V compiler') }
	mut args := ['-w', '-cc', 'clang', '-nocache', '-enable-globals', '-gc', 'none', '-manualfree',
		'-path', '@vlib|' + root + '/tools/accounts|@vmodules', '-o', work + '/check']
	if '--sanitize' in os.args {
		args << ['-cflags', '-fsanitize=address,undefined', '-ldflags', '-fsanitize=address,undefined']
	}
	args << work + '/main.v'
	mut compiler := os.new_process(v)
	compiler.set_args(args)
	compiler.run()
	compiler.wait()
	if compiler.code != 0 { return error('secret regression did not compile') }
	mut test := os.new_process(work + '/check')
	test.run()
	test.wait()
	if negative_reap {
		if test.code == 0 { return error('old nonblocking retirement unexpectedly passed') }
		println('PASS manager retirement negative control: old WNOHANG cleanup refused')
	} else if test.code != 0 {
		return error('secret regression failed')
	}
}

fn main() {
	check() or {
		eprintln(err)
		exit(1)
	}
}
