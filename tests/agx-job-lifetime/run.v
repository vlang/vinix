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
	scratch := os.join_path(os.temp_dir(), 'vinix-agx-lifetime-${os.getpid()}')
	os.mkdir_all(scratch)!
	defer { os.rmdir_all(scratch) or { panic(err) } }
	os.cp_all('${repo}/tests/agx-job-lifetime/fixture', scratch, false)!
	for name in ['klock', 'katomic'] {
		os.cp_all('${repo}/tests/agx-g13-failure/fixture/${name}', '${scratch}/${name}', false)!
	}
	os.write_file('${scratch}/klock/host.v', 'module klock\npub fn (guard &Lock) is_locked() bool { return guard.held }\n')!
	os.cp_all('${repo}/tests/agx-event/fixture/drm', '${scratch}/drm', false)!
	os.mkdir_all('${scratch}/gpu/agx')!
	os.cp_all('${repo}/kernel/gpu/agx/event', '${scratch}/gpu/agx/event', false)!
	os.cp('${repo}/kernel/gpu/agx/gpu/g13_tpc.v', '${scratch}/gpu/tpc.v')!
	os.cp('${repo}/kernel/gpu/agx/gpu/g13_barriers.v', '${scratch}/gpu/barrier_production.v')!
	os.cp('${repo}/kernel/gpu/agx/gpu/g13_initial.v', '${scratch}/gpu/initial_production.v')!
	os.cp('${repo}/kernel/gpu/agx/gpu/g13_admission.v', '${scratch}/gpu/admission_production.v')!
	os.cp('${repo}/kernel/gpu/agx/gpu/g13_batch.v', '${scratch}/gpu/batch_production.v')!
	os.mkdir_all('${scratch}/gpu/agx/channel')!
	os.cp('${repo}/kernel/gpu/agx/channel/channel.v', '${scratch}/gpu/agx/channel/channel.v')!
	os.write_file('${scratch}/gpu/agx/channel/host.v', 'module channel\n__global higher_half = u64(0)\n')!
	os.mkdir_all('${scratch}/gpu/agx/alloc')!
	allocator := os.read_file('${repo}/kernel/gpu/agx/alloc/alloc.v')!
	os.write_file('${scratch}/gpu/agx/alloc/constants.v', 'module alloc\n' + section(allocator, 'pub const g13_private_start', '// RTKit system endpoints')!)!
	os.write_file('${scratch}/gpu/agx/event/host.v', 'module event\n__global higher_half = u64(0)\npub fn test_force_refs(slot u32, value u32) u32 { old := gpu_event_mgr.stamps[slot].references; gpu_event_mgr.stamps[slot].references = value; return old }\n')!
	os.symlink('${repo}/kernel/gpu/agx/fw', '${scratch}/gpu/agx/fw')!
	source := os.read_file('${repo}/kernel/gpu/agx/gpu/g13.v')!
	mut production := 'module gpu\nimport gpu.agx.event\nimport gpu.agx.fw\nimport gpu.agx.mmu\nimport katomic\nimport klock\n'
	production += section(source, 'struct G13SubQueueResources {', 'struct G13RenderBufferResources {')!
	production += section(source, 'pub struct G13ComputeJobResources {', 'pub struct G13QueueResources {')!
	for pair in [
		['pub fn (queue &G13QueueResources) has_file_references(', '// Caller holds mgr.lock. Asahi QueueInner'],
		['fn (mut mgr GpuManager) g13_ring_has_space_locked(', '// Publish up to two prefix barriers'],
		['fn (mut mgr GpuManager) retire_g13_render_stages_locked(', 'fn build_g13_attachments('],
		['fn (mgr &GpuManager) g13_queue_dispatch_blocked_locked(', '// Caller holds the manager lock during shutdown.'],
		['fn (mut mgr GpuManager) free_g13_render_buffer_locked(', 'fn (mut mgr GpuManager) initialize_g13_render_buffer('],
		['fn (mut mgr GpuManager) reserve_g13_tvb_slot()', '// Caller holds mgr.lock. No submitted job'],
		['fn (mgr &GpuManager) g13_tvb_owner_locked(', '// Service firmware'],
		['pub fn (mut mgr GpuManager) release_g13_queue_resources(', '// Quarantined backing must retire'],
		['fn (mut mgr GpuManager) release_g13_render_scene_backing_locked(',
			'fn (mut mgr GpuManager) free_g13_render_scene_locked('],
		['fn (mut mgr GpuManager) free_g13_render_job_locked(', '// Construct the complete paired'],
		['pub fn (mut mgr GpuManager) release_g13_render_job(',
			'// Install the one-shot completion callback'],
		['fn (mut mgr GpuManager) reap_g13_render_jobs()',
			'pub fn (job &G13RenderJobResources) timestamp_values()'],
		['fn (mut mgr GpuManager) free_g13_compute_job_locked(', '// Construct one byte-exact G13'],
		['pub fn (mut mgr GpuManager) release_g13_compute_job(',
			'// Install the one-shot completion callback'],
		['fn (mut mgr GpuManager) reap_g13_compute_jobs()',
			'pub fn (job &G13ComputeJobResources) command_address()'],
	] {
		production += section(source, pair[0], pair[1])!
	}
	os.write_file('${scratch}/gpu/production.v', production)!
	os.cp('${repo}/tests/agx-job-lifetime/test.v', '${scratch}/main.v')!
	mut build := os.new_process(os.getenv_opt('V') or { 'v' })
	build.set_args(['-nocache', '-no-parallel', '-gc', 'none', '-cc', 'cc', '-enable-globals', '-path',
		'${scratch}|${repo}/kernel|@vlib|@vmodules', '-cflags',
		'-fsanitize=address,undefined -fno-omit-frame-pointer', '-ldflags',
		'-fsanitize=address,undefined', '-o', '${scratch}/test', '${scratch}/main.v'])
	build.run()
	build.wait()
	if build.code != 0 { exit(build.code) }
	if output := os.getenv_opt('AGX_LIFETIME_TEST_BINARY') { os.cp('${scratch}/test', output)! }
	mut check := os.new_process('${scratch}/test')
	check.run()
	check.wait()
	exit(check.code)
}
