// SPDX-License-Identifier: GPL-2.0-or-later
module g13contract

fn check_sync_file_info_contract(drm string, uapi string, implementation string, snapshot string, stub string) ! {
	request := section(drm, 'fn (mut this SyncFileResource) ioctl(', 'fn (mut this SyncFileResource) unref(', 'Sync-file info dispatch')!
	require_order(request, ['if u32(request) == ioctl.sync_ioc_file_info', 'sync_file_info_ioctl(this.fence, u64(argp))',
		'errno.set(u64(-result))', 'resource.default_ioctl'], 'Typed sync-file info dispatch')!
	require(integer_constant(uapi, 'sync_ioc_file_info', 'Sync-file info command')! == 0xc0383e04, 'Sync-file info command changed')!
	for pair in [['pub struct SyncFileInfo {', 'pub struct SyncFenceInfo {', 'name [32]u8', 'status i32', 'flags u32', 'num_fences u32', 'pad u32', 'sync_fence_info u64'],
		['pub struct SyncFenceInfo {', '\n}', 'obj_name [32]u8', 'driver_name [32]u8', 'status i32', 'flags u32', 'timestamp_ns u64']] {
		layout := section(uapi, pair[0], pair[1], 'Sync-file UAPI fields')!
		require_order(layout, pair[2..], 'Sync-file UAPI layout')!
	}
	require_order(snapshot, ['f.lock.acquire()', 'status: if !f.signaled { 0 } else if f.error != 0 { f.error } else { 1 }',
		'timestamp_ns: if f.signaled { f.timestamp_ns } else { 0 }', 'if f.private_stub { .stub } else if f.queue_context != 0 { .queue }',
		'f.lock.release()', 'return result'], 'Coherent leaf status/time and private provenance')!
	require_order(stub, ['fence.private_stub = true', 'katomic.store(mut &fence.signaled, true)'], 'Private stub provenance before publication')!
	require_order(implementation, ['mut digits := [20]u8{}', 'remaining % 10', 'remaining /= 10'], 'Fixed decimal storage')!
	require_order(implementation, [".stub { 'stub' } .queue { 'asahi' } .generic { 'vinix' }",
		".stub { 'stub' } .queue { 'queue' } .generic { 'fence' }", 'info.context', 'i64(info.seqno) < 0',
		'u64(-(i64(info.seqno) + 1)) + 1', 'file_name[offset] = 0'], 'Bounded signed fence names')!
	query := implementation.all_after('fn sync_file_info_ioctl(')
	require_order(query, ['usercopy.copy_from_user(', 'if info.flags != 0 || info.pad != 0 { return -22 }',
		'state := syncobj.snapshot(fence)', 'if info.num_fences == 0', 'info.status = i32(state.status)',
		'memory.malloc_packed_fallible(sizeof(ioctl.SyncFenceInfo))', 'if allocation == unsafe { nil } { return -12 }',
		'defer { memory.free(allocation) }', '*detail = ioctl.SyncFenceInfo{ status: i32(state.status), timestamp_ns: state.timestamp_ns }',
		'info.status = detail.status', 'usercopy.copy_to_user(info.sync_fence_info, detail, sizeof(ioctl.SyncFenceInfo))',
		'info.num_fences = 1', 'usercopy.copy_to_user(address, unsafe { &info }, sizeof(ioctl.SyncFileInfo))'],
		'Count-only fast path, owned detail cleanup and staged output order')!
}

fn check_sync_file_info_reference(reference string, header string, fences string, queues string) ! {
	for pair in [['struct sync_file_info {', '};', 'char\tname[32]', '__s32\tstatus', '__u32\tflags', '__u32\tnum_fences', '__u32\tpad', '__u64\tsync_fence_info'],
		['struct sync_fence_info {', '};', 'char\tobj_name[32]', 'char\tdriver_name[32]', '__s32\tstatus', '__u32\tflags', '__u64\ttimestamp_ns']] {
		require_order(section(header, pair[0], pair[1], 'Linux sync-file UAPI')!, pair[2..], 'Linux sync-file field order')!
	}
	require(header.contains("#define SYNC_IOC_MAGIC\t\t'>'") && header.contains('SYNC_IOC_FILE_INFO\t_IOWR(SYNC_IOC_MAGIC, 4, struct sync_file_info)'), 'Linux sync-file command changed')!
	query := section(reference, 'static long sync_file_ioctl_fence_info(', 'static int sync_file_ioctl_set_deadline(', 'Linux file-info query')!
	require_order(query, ['copy_from_user(&info,', 'if (info.flags || info.pad)', 'dma_fence_unwrap_for_each',
		'if (!info.num_fences)', 'dma_fence_get_status(sync_file->fence)', 'if (info.num_fences < num_fences)',
		'kzalloc(size, GFP_KERNEL)', 'sync_fill_fence_info(', 'copy_to_user(u64_to_user_ptr(info.sync_fence_info)',
		'sync_file_get_name(', 'info.num_fences = num_fences', 'copy_to_user((void __user *)arg, &info', 'kfree(fence_info)'], 'Linux file-info behavior')!
	require(reference.contains('"%s-%s%llu-%lld"') && reference.contains('dma_fence_timestamp(fence)'), 'Linux name/time semantics changed')!
	require(section(fences, 'static const char *dma_fence_stub_get_name(', 'static const struct dma_fence_ops dma_fence_stub_ops', 'Linux stub name')!.contains('return "stub";'), 'Linux stub name changed')!
	require_order(section(queues, 'impl dma_fence::FenceOps for JobFence::ver', 'pub(crate) struct QueueJob', 'Asahi underlying queue fence names')!,
		['fn get_driver_name', 'c_str!("asahi")', 'fn get_timeline_name', 'c_str!("queue")'], 'Asahi underlying queue names')!
}
