// SPDX-License-Identifier: GPL-2.0-or-later
module g13contract

fn check_wait_storage_contract(drm string, storage string, reference string) ! {
	wait := section(drm, 'fn ioctl_syncobj_wait(', 'fn ioctl_syncobj_reset(', 'Vinix counted binary waits')!
	require(!wait.contains('request.count_handles > 64 {\n\t\treturn'), 'Wait count must not be capped at the inline capacity')!
	require_order(wait, ['if request.count_handles == 0 { return 0 }', 'mut handles := [64]u32{}',
		'mut objects := unsafe { [64]voidptr{} }', 'mut captures := [64]syncobj.FenceCapture{}',
		'if request.count_handles > 64 {', 'new_syncobj_wait_buffer(request.count_handles)',
		'return -12', 'defer { buffer.free_owned() }', 'usercopy.copy_from_user(buffer.handles',
		'object := syncobj.lookup(', 'defer {', 'mut remaining := request.count_handles',
		'remaining--', 'syncobj.release_capture(', 'syncobj.prepare_capture('], 'Vinix inline/owned storage and unlink-before-free defer order')!
	geometry := section(storage, 'fn syncobj_wait_geometry(', 'struct SyncobjWaitBuffer', 'Vinix wait geometry')!
	require_order(geometry, ['count == 0', '(maximum - 15) / sizeof(u32)',
		'(count * sizeof(u32) + 15) & ~u64(15)',
		'(maximum - objects_offset) / sizeof(voidptr)', 'objects_end > maximum - 15',
		'(objects_end + 15) & ~u64(15)', '(maximum - captures_offset) / sizeof(syncobj.FenceCapture)',
		'bytes: captures_offset + count * sizeof(syncobj.FenceCapture)'], 'Vinix checked aligned wait-region geometry')!
	allocate := section(storage, 'fn new_syncobj_wait_buffer(', '// The caller must release', 'Vinix owned wait allocation')!
	require_order(allocate, ['syncobj_wait_geometry(u64(count))', 'memory.malloc_packed_fallible(geometry.bytes)',
		'if allocation == unsafe { nil } { return none }', 'C.memset(allocation, 0, geometry.bytes)',
		'return SyncobjWaitBuffer{', 'allocation: allocation', 'geometry.objects_offset',
		'geometry.captures_offset'], 'Vinix fallible zeroed owner transfer')!
	require(allocate.count('memory.malloc_packed_fallible(') == 1, 'Wait storage must have one allocation site')!
	free := storage.all_after('fn (mut buffer SyncobjWaitBuffer) free_owned()')
	require_order(free, ['if buffer.allocation != unsafe { nil }', 'memory.free(buffer.allocation)',
		'buffer.allocation = unsafe { nil }', 'buffer.handles = unsafe { nil }',
		'buffer.objects = unsafe { nil }', 'buffer.captures = unsafe { nil }'], 'Vinix idempotent owned storage retirement')!
	find := section(reference, 'static int drm_syncobj_array_find(', 'static void drm_syncobj_array_free(', 'Linux counted wait handles')!
	require_order(find, ['kmalloc_array(count_handles, sizeof(*handles)', 'return -ENOMEM',
		'copy_from_user(handles, user_handles', 'kmalloc_objs(*syncobjs, count_handles)', 'kfree(handles)'], 'Linux dynamically counted wait input storage')!
	ref_wait := section(reference, 'static signed long drm_syncobj_array_wait_timeout(', '* drm_timeout_abs_to_jiffies', 'Linux counted wait entries')!
	require_order(ref_wait, ['entries = kzalloc_objs(*entries, count)', 'timeout = -ENOMEM',
		'cleanup_entries:', 'drm_syncobj_remove_wait(syncobjs[i], &entries[i])', 'kfree(entries)'], 'Linux detachment before wait-entry storage retirement')!
}
