// SPDX-License-Identifier: GPL-2.0-or-later
module g13contract

fn check_signal_contract(drm string, wire string, stub string, reference string,
	fences string, header string) ! {
	require(integer_constant(wire, 'drm_ioctl_syncobj_signal', 'Vinix SIGNAL opcode')! == 0xc5,
		'Vinix SIGNAL opcode differs from Linux')!
	registration := section(drm, 'fn common_ioctl_layout(', 'fn ioctl_layout(', 'Vinix SIGNAL registration')!
	require_order(registration, ['ioctl.drm_ioctl_syncobj_signal {',
		'size: u32(sizeof(ioctl.DrmSyncobjArray)), direction: ioctl_write | ioctl_read'], 'Vinix SIGNAL wire registration')!
	require_order(drm.all_after('fn core_ioctl('), ['ioctl.drm_ioctl_syncobj_signal {',
		'return ioctl_syncobj_signal(handle, data)'], 'Vinix SIGNAL dispatch')!
	signal := section(drm, 'fn ioctl_syncobj_signal(', 'fn core_ioctl(', 'Vinix SIGNAL')!
	require_order(signal, ['request.pad != 0 || request.count_handles == 0', 'return -22',
		'mut handles := [64]u32{}', 'mut objects := unsafe { [64]voidptr{} }',
		'new_syncobj_handle_buffer(request.count_handles)', 'return -12', 'defer { buffer.free_owned() }',
		'usercopy.copy_from_user(buffer.handles, request.handles,', 'u64(request.count_handles) * sizeof(u32)',
		'return -14', 'defer { buffer.release_object_references(request.count_handles) }',
		'for i := u32(0); i < request.count_handles; i++ {',
		'object := syncobj.lookup_referenced(u64(handle), unsafe { buffer.handles[i] }) or { return -2 }',
		'buffer.objects[i] = voidptr(object)', '}',
		'for i := u32(0); i < request.count_handles; i++ {',
		'fence := syncobj.new_private_stub(syncobj.now_ns()) or { return -12 }',
		'syncobj.replace_fence(unsafe { &syncobj.SyncObj(buffer.objects[i]) }, fence)', 'return 0'],
		'Vinix validation before fresh per-entry completion and OOM prefix preservation')!
	require(signal.count('usercopy.copy_from_user(') == 1 && signal.count('syncobj.lookup_referenced(') == 1
		&& signal.count('syncobj.new_private_stub(') == 1 && !signal.contains('syncobj.signal('),
		'SIGNAL must replace heads without completing old GPU snapshots')!
	require_order(stub, ['pub fn new_private_stub(timestamp_ns u64)',
		'memory.malloc_packed_fallible(sizeof(DmaFence))', 'if allocation == unsafe { nil } { return none }',
		'&DmaFence(allocation)', '*fence = DmaFence{ timestamp_ns: timestamp_ns }',
		'katomic.store(mut &fence.signaled, true)', 'return fence'], 'Vinix fresh initialized private stub')!
	require(stub.count('memory.malloc_packed_fallible(') == 1 && !stub.contains('new_fence(')
		&& !stub.contains('__global') && !stub.contains('memory.free('), 'Private completions must be fresh and retained after publication')!
	macro := header.split_into_lines().filter(it.starts_with('#define DRM_IOCTL_SYNCOBJ_SIGNAL'))
	require(macro.len == 1 && macro[0].contains('DRM_IOWR(0xC5, struct drm_syncobj_array)'), 'Linux SIGNAL wire encoding changed')!
	ref_signal := section(reference, 'drm_syncobj_signal_ioctl(', 'drm_syncobj_timeline_signal_ioctl(', 'Linux SIGNAL')!
	require_order(ref_signal, ['if (args->pad != 0)', 'return -EINVAL', 'if (args->count_handles == 0)',
		'return -EINVAL', 'drm_syncobj_array_find(', 'if (ret < 0)', 'return ret',
		'for (i = 0; i < args->count_handles; i++)', 'ret = drm_syncobj_assign_null_handle(syncobjs[i])',
		'if (ret < 0)', 'break', 'drm_syncobj_array_free(syncobjs, args->count_handles)', 'return ret'],
		'Linux per-entry allocation and partial prefix failure')!
	assign := section(reference, 'static int drm_syncobj_assign_null_handle(', '/* 5s default', 'Linux private completion assignment')!
	require_order(assign, ['dma_fence_allocate_private_stub(ktime_get())', 'if (!fence)', 'return -ENOMEM',
		'drm_syncobj_replace_fence(syncobj, fence)', 'dma_fence_put(fence)'], 'Linux fresh timestamped success replaces head')!
	allocate := section(fences, 'struct dma_fence *dma_fence_allocate_private_stub(', 'EXPORT_SYMBOL(dma_fence_allocate_private_stub)', 'Linux private stub')!
	require_order(allocate, ['kzalloc_obj(*fence)', 'if (fence == NULL)', 'return NULL',
		'dma_fence_init(fence, &dma_fence_stub_ops, NULL, 0, 0)',
		'dma_fence_signal_timestamp(fence, timestamp)', 'return fence'], 'Linux fallible distinct timestamped private completion')!
}
