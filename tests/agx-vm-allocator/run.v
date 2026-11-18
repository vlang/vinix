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
	scratch := os.join_path(os.temp_dir(), 'vinix-agx-vm-allocator-${os.getpid()}')
	os.mkdir_all(scratch)!
	defer { os.rmdir_all(scratch) or { panic(err) } }
	os.cp_all('${repo}/tests/agx-vm-allocator/fixture', scratch, false)!
	os.cp_all('${repo}/tests/agx-tlb/fixture/klock', '${scratch}/klock', false)!
	os.symlink('${repo}/kernel/gpu/agx/vm', '${scratch}/gpu/agx/vm')!
	os.mkdir_all('${scratch}/drm')!
	os.symlink('${repo}/kernel/drm/ioctl', '${scratch}/drm/ioctl')!
	source := os.read_file(os.getenv_opt('AGX_VM_ALLOCATOR_MMU_SOURCE') or {
		'${repo}/kernel/gpu/agx/mmu/mmu.v'
	})!
	gate_import := if source.contains('admission.Gate') {
		// Keep the embedded layout. The allocator does not enter the gate.
		os.mkdir_all('${scratch}/gpu/agx/admission')!
		os.mkdir_all('${scratch}/event')!
		os.symlink('${repo}/kernel/event/eventstruct', '${scratch}/event/eventstruct')!
		gate := os.read_file('${repo}/kernel/gpu/agx/admission/admission.v')!
		os.write_file('${scratch}/gpu/agx/admission/layout.v', 'module admission\nimport event.eventstruct\n' +
			section(gate, 'pub struct Gate {', 'pub fn (mut gate Gate) try_enter(')!)!
		'import gpu.agx.admission\n'
	} else { '' }
	production := 'module mmu\n' + gate_import +
		'import gpu.agx.vm as agxvm\nimport gpu.agx.alloc as gpu_alloc\nimport gpu.agx.pgtable\nimport klock\nimport memory\n__global higher_half = u64(0)\n' +
		section(source, 'pub struct UatContext {', '// Driver-owned backing')! +
		section(source, 'pub struct UatBuffer {', 'pub struct UatManager {')! +
		section(source, 'pub fn (mut mgr UatManager) create_context(', '// Convert a cached driver allocation')! +
		section(source, 'fn (mut ctx UatContext) release_driver_buffer_locked(', '// Remove a driver-buffer translation')! +
		section(source, 'pub fn (mut ctx UatContext) release_driver_buffer(', 'pub fn (buffer &UatBuffer) cpu_address()')!
	os.write_file('${scratch}/gpu/agx/mmu/production.v', production)!
	os.cp('${repo}/tests/agx-vm-allocator/test.v', '${scratch}/main.v')!
	mut build := os.new_process(os.getenv_opt('V') or { 'v' })
	build.set_args(['-nocache', '-no-parallel', '-gc', 'none', '-manualfree', '-cc', 'cc', '-enable-globals',
		'-path', '${scratch}|@vlib|@vmodules', '-cflags',
		'-fsanitize=address,undefined -fno-omit-frame-pointer', '-ldflags',
		'-fsanitize=address,undefined', '-o', '${scratch}/test', '${scratch}/main.v'])
	build.run()
	build.wait()
	if build.code != 0 { exit(build.code) }
	if output := os.getenv_opt('AGX_VM_ALLOCATOR_BINARY') { os.cp('${scratch}/test', output)! }
	mut check := os.new_process('${scratch}/test')
	check.run()
	check.wait()
	exit(check.code)
}
