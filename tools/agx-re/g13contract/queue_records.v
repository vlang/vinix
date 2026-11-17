// SPDX-License-Identifier: GPL-2.0-or-later
module g13contract

fn check_queue_records_local(file string, queues string) ! {
	dispose := section(queues, 'pub fn free_g13_queue_record(', 'pub fn (mut mgr GpuManager) create_g13_queue_resources(', 'Final queue record disposal')!
	require_order(dispose, ['resources != unsafe { nil } && resources.released', '!resources.has_file_references()',
		'resources.context_next == unsafe { nil }', 'unsafe { free(resources) }'], 'Backing, captures and intrusive links retire before metadata')!
	require(dispose.count('free(resources)') == 1, 'Exactly one checked final-owner metadata free')!
	require(queues.contains('} @[freed]\n\tmut complete := false'), 'Constructor record allocation is verified across failure and final-owner paths')!
	close := section(file, 'pub fn (mut f GpuFile) close()', 'fn (mut f GpuFile) get_object_ref(', 'Final file owners')!
	require_order(close, ['f.lock.acquire()', 'for ownership in f.g13_queues',
		'if ownership.resources.has_file_references() { f.lock.release(); return false }',
		'for vm in f.vms', 'katomic.load(&vm.inflight) != 0',
		'manager == unsafe { nil } && (f.timestamp_objects.len != 0 || f.g13_queues.len != 0)',
		'gpu_manager.release_g13_queue_resources(ownership.resources)', 'f.retire_mapping_locked(index)',
		'for mut q in f.queues { q.destroy() }', 'for index := f.g13_queues.len - 1;',
		'ownership := f.g13_queues[index]', 'f.g13_queues.delete(index)',
		'gpu.free_g13_queue_record(ownership.resources)', 'unsafe { f.g13_queues.free() }'], 'Close retains all records through capture/backing/mapping failures and deletes each final row before disposal')!
	for pair in [['reap_detached_g13_queues_locked', 'fn (mut f GpuFile) reap_orphaned_g13_queues_locked()'],
		['reap_orphaned_g13_queues_locked', '// The registry lock pins']] {
		reap := section(file, 'fn (mut f GpuFile) ' + pair[0] + '()', pair[1], 'Owner reaper')!
		require_order(reap, ['has_file_references() { continue }',
			'if !gpu_manager.release_g13_queue_resources(ownership.resources) { continue }',
			'f.g13_queues.delete(', 'gpu.free_g13_queue_record(ownership.resources)'], 'Reapers remove owners only after captures and backing permit disposal')!
	}
}
