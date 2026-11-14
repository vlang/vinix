// SPDX-License-Identifier: GPL-2.0-or-later
import os

fn section(source string, start string, end string) !string {
	begin := source.index(start) or { return error('missing ${start}') }
	finish := source.index_after(end, begin + start.len) or { return error('missing ${end}') }
	return source[begin..finish]
}

fn main() {
	os.setenv('V_C_ERROR_BUG_REPORT_DISABLED', '1', true)
	repo := os.real_path(os.join_path(os.dir(@FILE), '../..'))
	scratch := os.join_path(os.temp_dir(), 'vinix-drm-wire-${os.getpid()}')
	os.mkdir_all(scratch)!
	defer { os.rmdir_all(scratch) or { panic(err) } }
	os.cp_all('${repo}/tests/drm-wire/fixture', scratch, false)!
	source := os.read_file('${repo}/kernel/drm/drm.v')!
	mut production := 'module drm\nimport usercopy\n'
	production += section(source, 'struct DrmIoctlLayout {', '// Linux ioctl direction bits')!
	production += section(source, 'fn ioctl_layout(', '// The node is /dev/dri/')!
	os.write_file('${scratch}/drm/production.v', production)!
	os.cp('${repo}/tests/drm-wire/test.v', '${scratch}/main.v')!
	mut build := os.new_process(os.getenv_opt('V') or { 'v' })
	build.set_args(['-nocache', '-no-parallel', '-cc', 'cc', '-enable-globals', '-path',
		'${scratch}|@vlib|@vmodules', '-cflags', '-fsanitize=address,undefined -fno-omit-frame-pointer',
		'-ldflags', '-fsanitize=address,undefined', '-o', '${scratch}/test', '${scratch}/main.v'])
	build.run()
	build.wait()
	if build.code != 0 { exit(build.code) }
	if output := os.getenv_opt('DRM_WIRE_TEST_BINARY') { os.cp('${scratch}/test', output)! }
	mut check := os.new_process('${scratch}/test')
	check.run()
	check.wait()
	exit(check.code)
}
