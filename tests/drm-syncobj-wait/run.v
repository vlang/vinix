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
	scratch := os.join_path(os.temp_dir(), 'vinix-drm-syncobj-wait-${os.getpid()}')
	os.mkdir_all(scratch)!
	defer { os.rmdir_all(scratch) or { panic(err) } }
	os.cp_all('${repo}/tests/drm-syncobj-wait/fixture', scratch, false)!
	os.cp_all('${repo}/kernel/drm/syncobj', '${scratch}/drm/syncobj', false)!
	os.cp_all('${repo}/kernel/drm/ioctl', '${scratch}/drm/ioctl', false)!
	os.cp_all('${repo}/tests/agx-file-close/fixture/klock', '${scratch}/klock', false)!
	os.cp_all('${repo}/tests/agx-async/fixture/katomic', '${scratch}/katomic', false)!
	source := os.read_file('${repo}/kernel/drm/drm.v')!
	production := 'module drm\nimport drm.ioctl\nimport drm.syncobj\nimport usercopy\nimport sched\nimport proc\nimport katomic\n' +
		section(source, 'fn ioctl_syncobj_create(', 'fn create_prime_fd(')! +
		section(source, 'fn ioctl_syncobj_wait(', 'fn core_ioctl(')!
	os.write_file('${scratch}/drm/production.v', production)!
	os.write_file('${scratch}/drm/registration.v', 'module drm\nimport drm.ioctl\n' +
		section(source, 'struct DrmIoctlLayout {', 'fn common_ioctl_layout(')! +
		section(source, 'fn common_ioctl_layout(', 'fn ioctl_layout(')!)!
	os.cp('${repo}/kernel/drm/wait_storage.v', '${scratch}/drm/wait_storage.v')!
	os.cp('${repo}/tests/drm-syncobj-wait/capture_checks.v', '${scratch}/drm/syncobj/capture_checks.v')!
	process_source := os.read_file('${repo}/kernel/proc/proc.v')!
	os.write_file('${scratch}/proc/production.v', 'module proc\nimport katomic\n' +
		section(process_source, 'pub fn pending_signals(', '// Read-mostly limits')!)!
	os.write_file('${scratch}/main.v', 'import drm\nfn main() { drm.run_wait_checks(); drm.run_large_wait_checks(); drm.run_reset_checks(); drm.run_signal_checks() }\n')!
	mut build := os.new_process(os.getenv_opt('V') or { 'v' })
	build.set_args(['-nocache', '-no-parallel', '-gc', 'none', '-cc', 'cc', '-enable-globals',
		'-path', '${scratch}|@vlib|@vmodules', '-cflags',
		'-fsanitize=address,undefined -fno-omit-frame-pointer', '-ldflags',
		'-fsanitize=address,undefined', '-o', '${scratch}/test', '${scratch}/main.v'])
	build.run()
	build.wait()
	if build.code != 0 { exit(build.code) }
	if output := os.getenv_opt('DRM_SYNCOBJ_WAIT_TEST_BINARY') { os.cp('${scratch}/test', output)! }
	mut check := os.new_process('${scratch}/test')
	check.run()
	check.wait()
	exit(check.code)
}
