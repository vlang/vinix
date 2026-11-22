// SPDX-License-Identifier: GPL-2.0-or-later
import os

fn section(source string, start string, end string) !string {
	begin := source.index(start) or { return error('missing production section: ${start}') }
	finish := source.index_after(end, begin + start.len) or { return error('missing production terminator: ${end}') }
	return source[begin..finish]
}

// Run the production DRM fdinfo formatting under sanitizers. The guest
// fixture covers client numbering through the VFS.
fn main() {
	os.setenv('V_C_ERROR_BUG_REPORT_DISABLED', '1', true)
	repo := os.real_path(os.join_path(os.dir(@FILE), '../..'))
	scratch := os.join_path(os.temp_dir(), 'vinix-drm-fdinfo-${os.getpid()}')
	os.mkdir_all('${scratch}/drm')!
	defer { os.rmdir_all(scratch) or { panic(err) } }
	os.mkdir_all('${scratch}/lib')!
	os.cp('${repo}/kernel/lib/text.v', '${scratch}/lib/text.v')!
	source := os.read_file(os.getenv_opt('DRM_FDINFO_SOURCE') or { '${repo}/kernel/drm/fdinfo.v' })!
	production := 'module drm\nimport lib\n' +
		section(source, 'pub struct MemoryStats {', 'fn ioctl_set_client_name(')! +
		'// drm_show_fdinfo(): the driver' + source.all_after('// drm_show_fdinfo(): the driver')
	os.write_file('${scratch}/drm/production.v', production)!
	os.cp('${repo}/tests/drm-fdinfo/check.v', '${scratch}/drm/check.v')!
	os.write_file('${scratch}/main.v', 'import drm\nfn main() { drm.run_checks() }\n')!
	mut build := os.new_process(os.getenv_opt('V') or { 'v' })
	build.set_args(['-nocache', '-no-parallel', '-gc', 'none', '-cc', 'cc', '-enable-globals',
		'-path', '${scratch}|@vlib|@vmodules', '-cflags',
		'-fsanitize=address,undefined -fno-omit-frame-pointer', '-ldflags',
		'-fsanitize=address,undefined', '-o', '${scratch}/test', '${scratch}/main.v'])
	build.run()
	build.wait()
	if build.code != 0 { exit(build.code) }
	mut check := os.new_process('${scratch}/test')
	check.run()
	check.wait()
	exit(check.code)
}
