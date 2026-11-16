// SPDX-License-Identifier: GPL-2.0-or-later
import os

fn main() {
	os.setenv('V_C_ERROR_BUG_REPORT_DISABLED', '1', true)
	repo := os.real_path(os.join_path(os.dir(@FILE), '../..'))
	scratch := os.join_path(os.temp_dir(), 'vinix-drm-fence-${os.getpid()}')
	os.mkdir_all(scratch)!
	defer { os.rmdir_all(scratch) or { panic(err) } }
	os.mkdir_all('${scratch}/drm')!
	os.cp_all('${repo}/kernel/drm/syncobj', '${scratch}/drm/syncobj', false)!
	os.cp('${repo}/tests/drm-fence/checks.v', '${scratch}/drm/syncobj/checks.v')!
	for name in ['katomic', 'sched', 'time', 'memory'] {
		os.cp_all('${repo}/tests/agx-async/fixture/${name}', '${scratch}/${name}', false)!
	}
	os.cp_all('${repo}/tests/agx-file-close/fixture/klock', '${scratch}/klock', false)!
	os.write_file('${scratch}/main.v', 'import drm.syncobj\nfn main() { syncobj.run_checks() }\n')!
	mut build := os.new_process(os.getenv_opt('V') or { 'v' })
	build.set_args(['-nocache', '-no-parallel', '-cc', 'cc', '-enable-globals', '-gc', 'none',
		'-path', '${scratch}|@vlib|@vmodules', '-cflags',
		'-fsanitize=address,undefined -fno-omit-frame-pointer', '-ldflags',
		'-fsanitize=address,undefined', '-o', '${scratch}/test', '${scratch}/main.v'])
	build.run()
	build.wait()
	if build.code != 0 { exit(build.code) }
	if output := os.getenv_opt('DRM_FENCE_TEST_BINARY') { os.cp('${scratch}/test', output)! }
	mut check := os.new_process('${scratch}/test')
	check.run()
	check.wait()
	exit(check.code)
}
