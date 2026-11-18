// SPDX-License-Identifier: GPL-2.0-or-later
module g13contract

fn check_timestamp_capture_local(file string, captures string, gpu string) ! {
	lookup := section(captures, 'fn (mut f GpuFile) capture_g13_timestamp(', 'fn release_timestamp_object(', 'Timestamp destination capture')!
	require_order(lookup, ['timestamp.handle == 0', 'return 0, G13TimestampCapture{}',
		'f.lock.acquire()', 'object.id != timestamp.handle || object.detached',
		'voidptr(f.registration_manager) != voidptr(manager)', 'return -19',
		'timestamp.offset > ~u32(0) - u32(8)', 'return -22',
		'u64(timestamp.offset) + 8 > object.size', 'return -34',
		'object.references++', 'va: object.va, address: object.va + u64(timestamp.offset)', 'return -2'],
		'Timestamp capture follows null/lookup/overflow/range ordering and retains a stable scalar identity')!
	require(!lookup.contains('% 8') && !lookup.contains('& 7'), 'Legacy firmware timestamps allow byte offsets')!
	batch := captures.all_after('fn (mut f GpuFile) capture_g13_timestamps(')
	require_order(batch, ['references.entries[pipe][phase].va != 0', 'return -22',
		'input[pipe].start', 'input[pipe].end', 'f.capture_g13_timestamp(timestamp, manager)',
		'if code != 0 { f.release_g13_timestamps(mut references); return code }',
		'references.entries[pipe][phase] = capture'], 'Owned output cannot be overwritten; failed prefixes roll back')!
	close := section(file, 'pub fn (mut f GpuFile) close()', 'fn (mut f GpuFile) import_object(', 'File timestamp capture ownership')!
	require_order(close, ['f.lock.acquire()', 'object.references != 0', 'f.lock.release(); return false',
		'release_timestamp_object(f.registration_manager, object)', 'f.timestamp_objects.free()',
		'mut manager := unsafe { f.registration_manager }'], 'Close releases uncaptured timestamps through their owner before unrelated cleanup')!
	drop := section(captures, 'fn release_timestamp_object(', '// Caller holds file.lock.', 'Timestamp backing release')!
	require_order(drop, ['mut owner := unsafe { manager }', 'owner.unmap_g13_timestamp_buffer(object.va, object.size)',
		'gem.unref(object.obj)'], 'Unmap the original VA before dropping its GEM reference')!
	reaper := section(captures, 'fn (mut f GpuFile) reap_detached_timestamp_objects_locked()', 'fn (mut f GpuFile) release_g13_timestamp(', 'Detached timestamp cleanup')!
	require_order(reaper, ['f.timestamp_objects.len - 1',
		'if !object.detached || object.references != 0 { continue }',
		'release_timestamp_object(f.registration_manager, object)',
		'f.timestamp_objects.delete(index)'], 'Detached timestamps retain backing until the final capture')!
	release := section(captures, 'fn (mut f GpuFile) release_g13_timestamp(', '// Run outside GpuManager.lock', 'Capture release')!
	require_order(release, ['capture.va == 0', 'f.lock.acquire()', 'f.timestamp_objects[index].va != capture.va',
		'f.timestamp_objects[index].references--', 'f.reap_detached_timestamp_objects_locked()'], 'Release resolves retained identities under the file lock')!
	mapper := section(gpu, 'pub fn (mut mgr GpuManager) map_g13_timestamp_buffer(', 'pub fn (mut mgr GpuManager) unmap_g13_timestamp_buffer(', 'Native timestamp aperture')!
	require_order(mapper, ['mgr.lock.acquire()', 'defer { mgr.lock.release() }',
		'if mgr.state == .stopped { return -19, 0 }',
		'mgr.g13_timestamp.alloc(size, alloc.gpu_page_size) or { return -28, 0 }',
		'code := mgr.uat.map_kernel_status(va, phys, size, pgtable.gpu_prot_fw_shared_rw)', 'if code != 0',
		'mgr.g13_timestamp.cancel_unpublished(va)', 'return code, 0', 'return 0, va'],
		'Timestamp aperture exhaustion and page-table status propagate through BIND')!
	require(!mapper.contains('mgr.g13_timestamp.gc(') && !mapper.contains('mgr.g13_timestamp.release('),
		'Failed timestamp map cancels only its unpublished VA')!
	unmap := section(gpu, 'pub fn (mut mgr GpuManager) unmap_g13_timestamp_buffer(', 'fn (mut mgr GpuManager) retire_g13_timestamp_aperture_locked(', 'Timestamp unmap')!
	require_order(unmap, ['mgr.lock.acquire()', 'defer { mgr.lock.release() }', 'if mgr.state == .stopped',
		'mgr.uat.unmap_kernel(va, size)', 'mgr.g13_timestamp.release(va)', 'mgr.g13_timestamp.gc()'],
		'Late release skips PTEs and reservations retired by shutdown')!
	retire := section(gpu, 'fn (mut mgr GpuManager) retire_g13_timestamp_aperture_locked(', 'fn alloc_fixed_buffer(', 'Timestamp aperture teardown')!
	require_order(retire, ['for reservation in mgr.g13_timestamp.allocations',
		'mgr.uat.unmap_kernel(reservation.va, reservation.size)', 'free(reservation)',
		'mgr.g13_timestamp.allocations.free()'],
		'Retire every old mapping and allocation through the original UAT')!
	shutdown := gpu.all_after('pub fn (mut mgr GpuManager) shutdown()')
	require_order(shutdown, ['mgr.lock.acquire()', 'mgr.lock.release()', 'if mgr.state == .stopped { return }',
		'mgr.state = .stopped', 'mgr.stop_firmware_cpus(mgr.firmware_roles)',
		'if mgr.hw_config.gpu_gen == .g13 { mgr.retire_g13_timestamp_aperture_locked() }', 'mgr.release_all_g13_render_jobs()'],
		'Drain the timestamp aperture under the shutdown lock after firmware stops')!
}

fn check_timestamp_capture_reference(common string, render string, compute string, file string) ! {
	require_order(common, ['if timestamp.handle == 0', 'return Ok(None)', '.get(timestamp.handle.try_into()?)',
		'.ok_or(ENOENT)?', '.clone()', 'core::mem::drop(guard)', 'offset.checked_add(8).ok_or(EINVAL)?',
		'return Err(ERANGE)', 'mapping: mapping.firmware_mapping()?'], 'Packaged timestamp lookup clones ownership before range validation')!
	require_order(render, ['vtx_user_timestamps.start = common::get_timestamp_object(objects, cmdbuf.ts_vtx.start)?',
		'vtx_user_timestamps.end = common::get_timestamp_object(objects, cmdbuf.ts_vtx.end)?',
		'frg_user_timestamps.start = common::get_timestamp_object(objects, cmdbuf.ts_frag.start)?',
		'frg_user_timestamps.end = common::get_timestamp_object(objects, cmdbuf.ts_frag.end)?'], 'Packaged render capture order')!
	require_order(compute, ['user_timestamps.start = common::get_timestamp_object(objects, cmdbuf.ts.start)?',
		'user_timestamps.end = common::get_timestamp_object(objects, cmdbuf.ts.end)?'], 'Packaged compute capture order')!
	unbound := section(file, 'pub(crate) fn do_gem_unbind_object(', '/// IOCTL: queue_create:', 'Packaged timestamp name removal')!
	require(unbound.contains('objects().remove(data.object_handle as usize)'), 'Timestamp namespace removal drops only its own reference')!
}
