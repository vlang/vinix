// SPDX-License-Identifier: GPL-2.0-or-later
import os

fn main() {
	os.setenv('V_C_ERROR_BUG_REPORT_DISABLED', '1', true)
	repo := os.real_path(os.join_path(os.dir(@FILE), '../..'))
	scratch := os.join_path(os.temp_dir(), 'vinix-g13-layouts-${os.getpid()}')
	os.mkdir_all(scratch)!
	defer { os.rmdir_all(scratch) or { panic(err) } }
	mut flags := ['-nocache', '-no-parallel', '-cc', 'cc', '-enable-globals', '-gc', 'none']
	$if arm64 {
		flags << ['-exclude', '${repo}/kernel/klock/klock_amd64.v', '-exclude', '${repo}/kernel/katomic/katomic_amd64.v']
	} $else $if amd64 {
		flags << ['-exclude', '${repo}/kernel/klock/klock_arm64.v', '-exclude', '${repo}/kernel/katomic/katomic_arm64.v']
	} $else { panic('unsupported host architecture') }
	flags << ['-path', '${repo}/kernel|@vlib|@vmodules',
		'-cflags', '-fsanitize=address,undefined -fno-omit-frame-pointer',
		'-ldflags', '-fsanitize=address,undefined', '-o', '${scratch}/test', '${repo}/tests/agx-g13-layouts/test.v']
	mut build := os.new_process(os.getenv_opt('V') or { 'v' })
	build.set_args(flags)
	build.run()
	build.wait()
	if build.code != 0 { exit(build.code) }
	if output := os.getenv_opt('AGX_LAYOUT_TEST_BINARY') { os.cp('${scratch}/test', output)! }
	mut check := os.new_process('${scratch}/test')
	check.run()
	check.wait()
	exit(check.code)
}
