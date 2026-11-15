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
	scratch := os.join_path(os.temp_dir(), 'vinix-agx-close-${os.getpid()}')
	os.mkdir_all(scratch)!
	defer { os.rmdir_all(scratch) or { panic(err) } }
	os.cp_all('${repo}/tests/agx-file-close/fixture', scratch, false)!
	for name in ['katomic'] {
		os.cp_all('${repo}/tests/agx-g13-failure/fixture/${name}', '${scratch}/${name}', false)!
	}
	for path in ['drm/ioctl', 'gpu/agx/bo', 'gpu/agx/vm'] {
		os.mkdir_all(os.dir('${scratch}/${path}'))!
		os.symlink('${repo}/kernel/${path}', '${scratch}/${path}')!
	}
	source := os.read_file('${repo}/kernel/gpu/agx/file/file.v')!
	production := 'module file\nimport drm\nimport drm.gem\nimport drm.ioctl\nimport gpu.agx.gpu\nimport gpu.agx.mmu\nimport gpu.agx.pgtable\nimport gpu.agx.vm as agxvm\nimport gpu.agx.workqueue\nimport katomic\n' +
		section(source, 'struct GpuMapping {', 'struct G17QueueOwnership {')! +
		section(source, 'pub fn release_handle(', 'pub fn new_gpu_file(')! +
		section(source, 'pub fn (mut f GpuFile) close()', 'fn (mut f GpuFile) import_object(')! +
		section(source, 'fn (mut f GpuFile) retire_mapping_locked(', '// Reserve a nonzero per-open queue ID.')! +
		section(source, 'fn (f &GpuFile) find_vm(', '// Firmware may retain both UAT translations')! +
		section(source, 'pub fn (mut f GpuFile) ioctl_vm_destroy(', 'pub fn (mut f GpuFile) ioctl_gem_create(')! +
		section(source, 'pub fn (mut f GpuFile) ioctl_gem_bind(', 'pub fn (f &GpuFile) ioctl_get_time(')!
	os.write_file('${scratch}/gpu/agx/file/production.v', production)!
	os.cp('${repo}/kernel/gpu/agx/file/closing.v', '${scratch}/gpu/agx/file/closing.v')!
	gpu_source := os.read_file('${repo}/kernel/gpu/agx/gpu/gpu.v')!
	os.write_file('${scratch}/gpu/agx/gpu/registration.v', 'module gpu\n' +
		section(gpu_source, 'pub fn (mut mgr GpuManager) queue_file_retirement(', 'fn (mut mgr GpuManager) reap_file_resources(')! +
		section(gpu_source, 'pub fn (mut mgr GpuManager) flush_g13_file_mapping(', '// Publish a G13 UAT invalidation through')!)!
	os.cp('${repo}/tests/agx-file-close/test.v', '${scratch}/main.v')!
	mut build := os.new_process(os.getenv_opt('V') or { 'v' })
	build.set_args(['-nocache', '-no-parallel', '-gc', 'none', '-cc', 'cc', '-enable-globals',
		'-path', '${scratch}|@vlib|@vmodules', '-cflags',
		'-fsanitize=address,undefined -fno-omit-frame-pointer', '-ldflags',
		'-fsanitize=address,undefined', '-o', '${scratch}/test', '${scratch}/main.v'])
	build.run()
	build.wait()
	if build.code != 0 { exit(build.code) }
	if output := os.getenv_opt('AGX_CLOSE_TEST_BINARY') { os.cp('${scratch}/test', output)! }
	mut check := os.new_process('${scratch}/test')
	check.run()
	check.wait()
	exit(check.code)
}
