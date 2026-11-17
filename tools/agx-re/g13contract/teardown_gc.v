// SPDX-License-Identifier: GPL-2.0-or-later
module g13contract

fn check_teardown_gc_local(source string, manager string) ! {
	for name in ['free_g13_render_buffer_locked', 'free_g13_queue_resources_locked',
		'free_g13_render_job_locked', 'free_g13_compute_job_locked'] {
		body := section(source, 'fn (mut mgr GpuManager) ' + name + '(', '\n}\n', 'Deferred teardown')!
		require(!body.contains('mgr.g13_private.gc()') && !body.contains('mgr.g13_gpu_readonly.gc()'), 'Normal teardown cannot drain private pending ranges: ' + name)!
		require(body.contains('mgr.g13_shared.gc()'), 'Shared immediate-release behavior is retained')!
	}
	channels := section(manager, 'fn (mut mgr GpuManager) free_g13_channel_allocations(', '\n}\n', 'Channel drain')!
	require_order(channels, ['mgr.free_shared_buffer(', 'mgr.g13_private.gc()', 'mgr.g13_gpu_readonly.gc()'], 'Explicit channel teardown still drains deferred heaps')!
	events := section(source, 'fn (mut mgr GpuManager) release_g13_event_resources_locked()', '\n}\n', 'Event drain')!
	require_order(events, ['event.reset_event_manager()', 'mgr.free_shared_buffer(', 'mgr.g13_private.gc()'], 'Final event teardown still drains its deferred stamp owner')!
	shutdown := section(manager, 'pub fn (mut mgr GpuManager) shutdown()', '\n}\n', 'Stopped firmware drain')!
	require_order(shutdown, ['mgr.state = .stopped', 'mgr.stop_firmware_cpus(', 'mgr.release_all_g13_render_jobs()',
		'mgr.release_all_g13_compute_jobs()', 'mgr.release_all_g13_queue_resources()', 'mgr.release_g13_channels()', 'mgr.release_g13_event_resources_locked()'], 'Stopped firmware drains pending job/queue ranges before channel/event ownership ends')!
	init := section(manager, 'fn (mut mgr GpuManager) fail_g13_initialization()', '\n}\n', 'Initialization failure drain')!
	require_order(init, ['mgr.stop_firmware_cpus(', 'mgr.release_g13_channels()', 'mgr.release_g13_event_resources_locked()'], 'Initialization failure retains its stopped/unpublished drain')!
}

fn check_teardown_gc_reference(allocator string, manager string) ! {
	drop := section(allocator, 'impl Drop for HeapAllocation {', 'impl mm::AllocInner<HeapAllocationInner>', 'Asahi deferred owner drop')!
	require_order(drop, ['self.0.take().unwrap()', 'if let Some(garbage)', 'garbage.push(node, GFP_KERNEL)', 'None'], 'Private owner destruction transfers its node to pending garbage')!
	require(!drop.contains('collect_garbage('), 'Asahi owner drop does not collect unrelated pending nodes')!
	require(manager.count('.collect_garbage(') == 4, 'Asahi manager collects private prefixes only at context invalidation and threshold barriers')!
}
