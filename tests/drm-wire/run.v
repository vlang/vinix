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
	os.cp_all('${repo}/kernel/drm/ioctl', '${scratch}/drm/ioctl', false)!
	os.cp_all('${repo}/tests/agx-g13-failure/fixture/katomic', '${scratch}/katomic', false)!
	source := os.read_file(os.getenv_opt('DRM_WIRE_SOURCE') or { '${repo}/kernel/drm/drm.v' })!
	mut production := 'module drm\nimport drm.ioctl\nimport usercopy\nimport memory\nimport errno\n'
	production += 'import katomic\n'
	production += section(source, 'pub const driver_gem', 'pub struct DrmIoctl {')!
	production += section(source, 'pub const default_driver_date', 'pub struct DrmDriver {')!
	production += section(source, 'fn copy_version_field(', 'fn ioctl_gem_close(')!
	production += section(source, 'fn decode_ioctl_cmd(', '// The node is /dev/dri/')!
	production += section(source, 'fn (mut this DrmNode) ioctl(', 'fn (mut this DrmNode) unref(')!
	production += section(source, 'pub fn (dev &DrmDevice) is_registered(', '// Forward-reference placeholder')!
	production += section(source, 'fn (mut this DrmNode) open(', 'fn (mut this DrmNode) mapping_attributes(')!.replace('resource.Resource', 'NodeBox')
	production += section(source, 'fn remove_device_node(', 'fn (mut this DrmNode) open(')!
		.replace('fs.devtmpfs_remove_device(', 'devtmpfs_remove_device(')
	production += section(source, 'fn (mut this DrmNode) admit_mapping_range(', 'fn (mut this DrmNode) read(')!
		.replace('mmap.map_shared', 'map_shared')
	production += section(source, 'pub fn register_driver_with_data(', 'fn copy_version_field(')!
		.replace('syncobj.shared_timeline_stub()', 'shared_timeline_stub()').replace('C.kprintf(', 'C.printf(')
	assert source.contains('\npub fn get_device(')
	production += 'pub fn get_device(' + source.all_after('\npub fn get_device(')
	os.write_file('${scratch}/drm/production.v', production)!
	agx_source := os.read_file(os.getenv_opt('AGX_DRM_DRIVER_SOURCE') or {
		'${repo}/kernel/gpu/agx/driver/driver.v'
	})!
	chip_check := section(agx_source, '\tbase_m1 :=', '\tmut features :=')!
	metadata := section(agx_source, 'agx_drm_driver := &drm.DrmDriver{', '\t\tfeatures: features')!
		.all_after('{').replace('drm.default_driver_date', 'default_driver_date')
	os.write_file('${scratch}/drm/agx_metadata.v', 'module drm\nfn agx_metadata(chip_id u32) DrmDriver {\n${chip_check}\treturn DrmDriver{${metadata}\t}\n}\n')!
	os.cp('${repo}/tests/drm-wire/test.v', '${scratch}/main.v')!
	mut build := os.new_process(os.getenv_opt('V') or { 'v' })
	build.set_args(['-nocache', '-no-parallel', '-gc', 'none', '-cc', 'cc', '-enable-globals',
		'-path', '${scratch}|@vlib|@vmodules', '-cflags',
		'-fsanitize=address,undefined -fno-omit-frame-pointer', '-ldflags',
		'-fsanitize=address,undefined', '-o', '${scratch}/test', '${scratch}/main.v'])
	build.run()
	build.wait()
	if build.code != 0 { exit(build.code) }
	if output := os.getenv_opt('DRM_WIRE_TEST_BINARY') { os.cp('${scratch}/test', output)! }
	mut check := os.new_process('${scratch}/test')
	check.run()
	check.wait()
	exit(check.code)
}
