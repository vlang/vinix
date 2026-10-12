// SPDX-License-Identifier: GPL-2.0-or-later
module main

import os

fn main() {
	root := os.real_path(os.join_path(os.dir(@FILE), '..', '..'))
	work := os.join_path(os.temp_dir(), 'vinix-rtl8169-${os.getpid()}')
	os.mkdir_all(work) or { panic(err) }
	defer { os.rmdir_all(work) or {} }
	for source in os.ls(os.join_path(root, 'kernel/dev/rtl8169')) or { panic(err) } {
		if !source.ends_with('.v') || source == 'registers_amd64.v' { continue }
		name := if source == 'rtl8169_amd64.v' { 'rtl8169.v' } else { source }
		os.cp(os.join_path(root, 'kernel/dev/rtl8169', source), os.join_path(work, name)) or { panic(err) }
	}
	for entry in ['core_test.v', 'registers.v'] {
		os.cp(os.join_path(root, 'tests/rtl8169/fixture', entry), os.join_path(work, entry)) or { panic(err) }
	}
	for name in ['devcore', 'dma', 'klock', 'socket/inet'] {
		os.mkdir_all(os.join_path(work, name)) or { panic(err) }
		os.cp(os.join_path(root, 'tests/rtl8169/fixture', name, 'core.v'), os.join_path(work, name, 'core.v')) or { panic(err) }
	}
	os.write_file(os.join_path(work, 'v.mod'), "Module { name: 'rtl8169_fixture' }") or { panic(err) }
	compiler := os.getenv_opt('V') or { @VEXE }
	mut p := os.new_process(compiler)
	p.set_args(['-nocache', '-enable-globals', '-cc', 'clang', '-path', '@vlib|${work}', 'test', work])
	p.set_redirect_stdio()
	p.run()
	p.wait()
	print(p.stdout_slurp())
	eprint(p.stderr_slurp())
	code := p.code
	p.close()
	if code != 0 { exit(code) }
}
