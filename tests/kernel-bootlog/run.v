// SPDX-License-Identifier: GPL-2.0-or-later
module main

import os

fn main() {
	root := os.real_path(os.join_path(os.dir(@FILE), '..', '..'))
	work := os.join_path(os.temp_dir(), 'vinix-bootlog-${os.getpid()}')
	os.mkdir_all(os.join_path(work, 'lib')) or { panic(err) }
	defer { os.rmdir_all(work) or {} }
	os.cp(os.join_path(root, 'kernel/kprint/bootlog.v'), os.join_path(work, 'bootlog.v')) or { panic(err) }
	os.cp(os.join_path(root, 'kernel/lib/text.v'), os.join_path(work, 'lib/text.v')) or { panic(err) }
	os.cp(os.join_path(root, 'tests/kernel-bootlog/core_test.v'), os.join_path(work, 'core_test.v')) or { panic(err) }
	os.write_file(os.join_path(work, 'v.mod'), "Module { name: 'bootlog_fixture' }") or { panic(err) }
	mut p := os.new_process(os.getenv_opt('V') or { @VEXE })
	p.set_args(['-enable-globals', '-cc', 'clang', '-path', '@vlib|${work}', 'test', work])
	p.set_redirect_stdio()
	p.run()
	p.wait()
	print(p.stdout_slurp())
	eprint(p.stderr_slurp())
	code := p.code
	p.close()
	if code != 0 { exit(code) }
}
