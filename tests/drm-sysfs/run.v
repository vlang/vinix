// SPDX-License-Identifier: GPL-2.0-or-later
import os

fn section(source string, start string, end string) !string {
	begin := source.index(start) or { return error('missing section: ${start}') }
	finish := source.index_after(end, begin + start.len) or { return error('missing terminator: ${end}') }
	return source[begin..finish]
}

// Build the production DRM sysfs publisher and the AGX parent's identity
// against a recording /sys, then walk the result the way libdrm does.
fn main() {
	os.setenv('V_C_ERROR_BUG_REPORT_DISABLED', '1', true)
	assert os.args.len == 3 && os.args[1] == '--asahi-linux', 'usage: run.v --asahi-linux PATH'
	repo := os.real_path(os.join_path(os.dir(@FILE), '../..'))
	dtsi := os.read_file(os.join_path(os.args[2], 'arch/arm64/boot/dts/apple/t8103.dtsi'))!
	soc := section(dtsi, '\tsoc {', '\n\t};\n')!
	node := section(soc, 'gpu: gpu@', '};')!
	unit := node.all_after('gpu: gpu@').all_before(' ')
	compatible_line := section(node, 'compatible = ', ';')!
	// compatible = "apple,agx-t8103", "apple,agx-g13g": the quoted values.
	mut joined := []string{}
	for index, value in compatible_line.all_after('compatible = ').split('"') {
		if index % 2 == 1 { joined << value }
	}
	oracle := 'module drm\n\n// Generated from the pinned t8103.dtsi by tests/drm-sysfs/run.v.\n' +
		'const oracle_unit = \'${unit}\'\nconst oracle_node = \'gpu\'\nconst oracle_compatible = ${joined}\n'

	scratch := os.join_path(os.temp_dir(), 'vinix-drm-sysfs-${os.getpid()}')
	os.mkdir_all('${scratch}/drm')!
	defer { os.rmdir_all(scratch) or { panic(err) } }
	os.mkdir_all('${scratch}/lib')!
	os.cp('${repo}/kernel/lib/text.v', '${scratch}/lib/text.v')!
	os.mkdir_all('${scratch}/fs')!
	os.cp('${repo}/tests/drm-sysfs/fakefs.v', '${scratch}/fs/fakefs.v')!
	drm_source := os.read_file(os.getenv_opt('DRM_SYSFS_SOURCE') or { '${repo}/kernel/drm/sysfs.v' })!
	agx_source := os.read_file(os.getenv_opt('AGX_SYSFS_SOURCE') or { '${repo}/kernel/gpu/agx/driver/sysfs.v' })!
	// Linux names the device after the node's unit address: its first register
	// range, the ASC, not the SGX range the driver maps as gpu_mmio_base.
	driver_source := os.read_file(os.getenv_opt('AGX_DRIVER_SOURCE') or { '${repo}/kernel/gpu/agx/driver/driver.v' })!
	assert driver_source.contains('agx_driver_inst.unit_address = platform.asc_base'), 'unit address must be the ASC base'
	assert driver_source.contains('sysfs_parent: if base_m1 { gpu_sysfs_path(platform.asc_base) }'), 'DRM parent must be named from the ASC base'
	assert !agx_source.contains('gpu_mmio_base'), 'the sysfs name must not come from the SGX base'
	subsystem := section(agx_source, 'fs.sysfs_link(subsystem, \'', '\')')!.all_after('\'')
	// The VirtIO-MMIO GPU's devices, and that virtio-gpu names its DRM parent
	// with them.
	virtio_source := os.read_file(os.getenv_opt('VIRTIO_SYSFS_SOURCE') or { '${repo}/kernel/aarch64/virtio_gpu/sysfs.v' })!
	virtio_driver := os.read_file('${repo}/kernel/aarch64/virtio_gpu/virtio_gpu.v')!
	assert virtio_driver.contains('virtio_device_path(virtgpu_transport.unit_address, virtgpu_transport.slot)'), 'virtio-gpu must name its DRM parent'
	assert virtio_driver.contains('publish_virtio_sysfs(virtgpu_transport.unit_address'), 'virtio-gpu must publish its devices'
	production := 'module drm\nimport fs\nimport lib\n' + 'const drm_major' +
		drm_source.all_after('\nconst drm_major') + '\n' +
		section(agx_source, 'const t8103_compatible', '// The platform device\'s own files')! +
		section(agx_source, 'fn gpu_modalias()', '// Removal waits')! +
		'const agx_subsystem_link = \'${subsystem}\'\n' + virtio_source.all_after('import lib\n')
	os.write_file('${scratch}/drm/production.v', production)!
	os.write_file('${scratch}/drm/oracle.v', oracle)!
	os.cp('${repo}/tests/drm-sysfs/check.v', '${scratch}/drm/check.v')!
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
