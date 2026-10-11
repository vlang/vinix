// SPDX-License-Identifier: GPL-2.0-or-later
// Bootstrap the native workflow tools with a stable V compiler. The selected
// production compiler still generates every application and test.
module main
import os

fn command(program string, args []string) {
	mut p := os.new_process(program)
	p.set_args(args)
	p.run()
	p.wait()
	code := p.code
	p.close()
	if code != 0 { exit(code) }
}

fn main() {
	if os.args.len < 2 { eprintln('usage: workflow_driver.v check|publish [arguments]'); exit(2) }
	mode := os.args[1]
	if mode !in ['check', 'publish'] { exit(2) }
	root := os.real_path('.')
	v := os.getenv('V')
	if v == '' { eprintln('Set V to the production compiler'); exit(2) }
	os.setenv('VEXE', v, true)
	work := os.join_path(os.temp_dir(), 'vinix-workflow-driver-${os.getpid()}')
	os.mkdir_all(work) or { panic(err) }
	defer { os.rmdir_all(work) or {} }
	source := '${work}/tool.c'
	command(v, ['-new-compiler', '-target-libc-headers', '-gc', 'none', '-manualfree', '-path', '@vlib|@vmodules|${root}/tests/linuxkpi', '-o', source, '${root}/desktop/tools/workflow_${mode}.v'])
	mut c := os.read_file(source) or { panic(err) }
	$if macos { c = c.replace('ptrdiff_t offset);', 'int64_t offset);') }
	os.write_file(source, c) or { panic(err) }
	command('clang', ['-w', '-O1', source, '-lpthread', '-lm', '-o', '${work}/tool'])
	command('${work}/tool', os.args[2..])
}
