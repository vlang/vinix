// SPDX-License-Identifier: GPL-2.0-or-later
import os

fn main() {
	os.setenv('V_C_ERROR_BUG_REPORT_DISABLED', '1', true)
	repo := os.real_path(os.join_path(os.dir(@FILE), '../..'))
	scratch := os.join_path(os.temp_dir(), 'vinix-agx-vm-${os.getpid()}')
	os.mkdir_all(scratch)!
	defer { os.rmdir_all(scratch) or { panic(err) } }
	mut build := os.new_process(os.getenv_opt('V') or { 'v' })
	build.set_args(['-nocache', '-no-parallel', '-gc', 'none', '-cc', 'cc',
		'-path', '${repo}/kernel|@vlib|@vmodules',
		'-cflags', '-fsanitize=address,undefined -fno-omit-frame-pointer',
		'-ldflags', '-fsanitize=address,undefined', '-o', '${scratch}/test', '${repo}/tests/agx-vm/test.v'])
	build.run(); build.wait()
	if build.code != 0 { exit(build.code) }
	if output := os.getenv_opt('AGX_VM_TEST_BINARY') { os.cp('${scratch}/test', output)! }
	mut check := os.new_process('${scratch}/test')
	check.run(); check.wait()
	exit(check.code)
}
