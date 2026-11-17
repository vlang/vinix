// SPDX-License-Identifier: GPL-2.0-or-later
import os

fn section(source string, start string, end string) !string {
	a := source.index(start) or { return error(start) }; b := source.index_after(end, a + start.len) or { return error(end) }; return source[a..b]
}
fn run_checks() !int {
	assert os.args.len == 1 || os.args.len == 3 && os.args[1] == '--source'
	repo := os.real_path(os.join_path(os.dir(@FILE), '../..'))
	source := os.read_file(if os.args.len == 3 { os.args[2] } else { repo + '/kernel/gpu/agx/gpu/g13.v' })!
	manager := os.read_file(repo + '/kernel/gpu/agx/gpu/gpu.v')!
	scratch := os.join_path(os.temp_dir(), 'vinix-agx-teardown-${os.getpid()}')
	assert !os.exists(scratch); os.mkdir_all(scratch)!
	defer { os.rmdir_all(scratch) or { panic(err) } }
	os.cp_all(repo + '/tests/agx-heap-gc/fixture', scratch, false)!
	fixture := os.read_file(scratch + '/gpu/fixture.v')!
	fields := '\tg13_shared alloc.HeapAllocator\n\tg13_readonly alloc.HeapAllocator\n\tallocs alloc.HeapAllocator\n\tg13_rtkit alloc.HeapAllocator\n\tteardown_refuse bool\n\tteardown_owned []OwnedBuffer\n\tg13_tvb_slots [fw.g13_tvb_slot_count]bool\n\tg13_tvb_free_order [fw.g13_tvb_slot_count]u64\n\tg13_tvb_release_clock u64\n'
	os.write_file(scratch + '/gpu/fixture.v', fixture.replace('\tg13_gpu_readonly alloc.HeapAllocator\n', '\tg13_gpu_readonly alloc.HeapAllocator\n' + fields))!
	os.cp(repo + '/tests/agx-teardown-gc/teardown.v', scratch + '/gpu/teardown.v')!
	os.cp(repo + '/tests/agx-teardown-gc/types.v', scratch + '/gpu/types.v')!
	os.write_file(scratch + '/main.v', 'import gpu\nfn main() { gpu.check_teardown_gc() }\n')!
	for name in ['alloc', 'channel', 'fw'] {
		os.mkdir_all(scratch + '/gpu/agx/' + name)!
		filename := if name == 'fw' { 'channels.v' } else { name + '.v' }
		os.cp(repo + '/kernel/gpu/agx/' + name + '/' + filename, scratch + '/gpu/agx/' + name + '/' + filename)!
	}
	os.symlink(repo + '/kernel/gpu/agx/hw', scratch + '/gpu/agx/hw')!
	wire_buffer := os.read_file(repo + '/kernel/gpu/agx/fw/buffer.v')!
	constant := section(wire_buffer, 'pub const g13_tvb_slot_count', '\n')!
	os.write_file(scratch + '/gpu/agx/fw/slot_count.v', 'module fw\n' + constant + '\n')!
	os.mkdir_all(scratch + '/gpu/agx/mmu')!; os.cp(repo + '/tests/agx-teardown-gc/mmu.v', scratch + '/gpu/agx/mmu/fixture.v')!
	os.mkdir_all(scratch + '/memory')!; os.cp(repo + '/tests/agx-teardown-gc/memory.v', scratch + '/memory/fixture.v')!
	os.mkdir_all(scratch + '/katomic')!; os.cp(repo + '/tests/agx-g13-failure/fixture/katomic/atomic.v', scratch + '/katomic/atomic.v')!
	os.write_file(scratch + '/gpu/agx/channel/host.v', 'module channel\n__global higher_half = u64(0)\n')!
	mut production := 'module gpu\nimport gpu.agx.alloc\nimport gpu.agx.mmu\nimport gpu.agx.fw\nimport memory\n'
	production += section(manager, 'const buffer_allocator_default', '// GPU states')!
	production += section(manager, 'struct SharedBuffer {', '@[inline]')!
	production += section(manager, 'fn unmap_shared_buffer(', '// Perform the cache-safe teardown')!
	production += section(manager, 'fn (mut mgr GpuManager) release_shared_buffer_backing(', 'fn (mut mgr GpuManager) release_rtkit_buffers(')!
	for pair in [
		['fn (mut mgr GpuManager) free_g13_render_buffer_locked(', 'fn (mut mgr GpuManager) initialize_g13_render_buffer('],
		['fn (mut mgr GpuManager) free_g13_queue_resources_locked(', '// Caller holds the manager and subqueue locks.'],
		['fn (mut mgr GpuManager) free_g13_render_job_locked(', 'fn complete_g13_render_job('],
		['fn (mut mgr GpuManager) free_g13_compute_job_locked(', 'fn complete_g13_compute_job('],
		['fn (mut mgr GpuManager) release_g13_render_scene_backing_locked(', 'fn (mut mgr GpuManager) free_g13_render_scene_locked('],
		['fn (mut mgr GpuManager) release_g13_scene_slot_locked(', '// Caller holds mgr.lock. No submitted job'],
	] { production += section(source, pair[0], pair[1])! }
	os.write_file(scratch + '/gpu/production.v', production.replace(' / page_size', ' / teardown_host_page_size'))!
	os.cp(repo + '/kernel/gpu/agx/gpu/g13_garbage.v', scratch + '/gpu/garbage.v')!
	compiler := os.getenv_opt('V') or { 'v' }
	flags := ['-nocache', '-no-parallel', '-gc', 'none', '-manualfree', '-cc', 'cc', '-enable-globals', '-path', scratch + '|@vlib|@vmodules',
		'-cflags', '-fsanitize=address,undefined -fno-omit-frame-pointer', '-ldflags', '-fsanitize=address,undefined']
	mut p := os.new_process(compiler); mut args := flags.clone(); args << ['-o', scratch + '/test', scratch + '/main.v']; p.set_args(args); p.run(); p.wait(); if p.code != 0 { return p.code }; p.close()
	if target := os.getenv_opt('AGX_TEARDOWN_C') { mut c := os.new_process(compiler); mut args_c := flags.clone(); args_c << ['-o', target, scratch + '/main.v']; c.set_args(args_c); c.run(); c.wait(); if c.code != 0 { return c.code }; c.close() }
	if target := os.getenv_opt('AGX_TEARDOWN_BINARY') { os.cp(scratch + '/test', target)! }
	mut test := os.new_process(scratch + '/test'); test.run(); test.wait(); return test.code
}
fn main() { code := run_checks() or { panic(err) }; assert !os.exists(os.join_path(os.temp_dir(), 'vinix-agx-teardown-${os.getpid()}')); exit(code) }
