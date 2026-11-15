// SPDX-License-Identifier: GPL-2.0-or-later
module g13contract

fn check_reset_contract(drm string, wire string, storage string, sync string,
	reference string, header string) ! {
	require(integer_constant(wire, 'drm_ioctl_syncobj_reset', 'Vinix RESET opcode')! == 0xc4,
		'Vinix RESET opcode differs from Linux')!
	fields := section(wire, 'pub struct DrmSyncobjArray {', '// include/uapi/drm/drm_mode.h', 'Vinix RESET array')!
	require_order(fields, ['handles       u64', 'count_handles u32', 'pad           u32'], 'Vinix RESET wire fields')!
	require(wire.contains('sizeof(DrmSyncobjArray) == 16'), 'Missing RESET layout guard')!
	registration := section(drm, 'fn common_ioctl_layout(', 'fn ioctl_layout(', 'Vinix RESET registration')!
	require_order(registration, ['ioctl.drm_ioctl_syncobj_reset {', 'size: u32(sizeof(ioctl.DrmSyncobjArray)), direction: ioctl_write | ioctl_read'], 'Vinix RESET size/direction')!
	dispatch := drm.all_after('fn core_ioctl(')
	require_order(dispatch, ['ioctl.drm_ioctl_syncobj_reset {', 'return ioctl_syncobj_reset(handle, data)'], 'Vinix RESET dispatch')!
	reset := section(drm, 'fn ioctl_syncobj_reset(', 'fn core_ioctl(', 'Vinix RESET handler')!
	require_order(reset, ['if request.pad != 0 || request.count_handles == 0 { return -22 }',
		'mut handles := [64]u32{}', 'mut objects := unsafe { [64]voidptr{} }',
		'if request.count_handles > 64 {', 'new_syncobj_handle_buffer(request.count_handles)',
		'return -12', 'defer { buffer.free_owned() }', 'usercopy.copy_from_user(buffer.handles, request.handles,',
		'u64(request.count_handles) * sizeof(u32)', 'return -14',
		'for i := u32(0); i < request.count_handles; i++ {',
		'object := syncobj.lookup(u64(handle), unsafe { buffer.handles[i] }) or { return -2 }',
		'buffer.objects[i] = voidptr(object)', '}',
		'for i := u32(0); i < request.count_handles; i++ {',
		'syncobj.replace_fence(unsafe { &syncobj.SyncObj(buffer.objects[i]) }, unsafe { nil })',
		'return 0'], 'Vinix all handle identities before sequential nil replacement')!
	require(reset.count('usercopy.copy_from_user(') == 1 && reset.count('syncobj.lookup(') == 1
		&& reset.count('syncobj.replace_fence(') == 1 && !reset.contains('syncobj.signal'),
		'RESET must snapshot once without signaling old fences')!
	allocate := section(storage, 'fn new_syncobj_handle_buffer(', 'fn new_syncobj_wait_buffer(', 'Vinix RESET owner')!
	require_order(allocate, ['syncobj_wait_geometry(u64(count))',
		'memory.malloc_packed_fallible(geometry.captures_offset)',
		'if allocation == unsafe { nil } { return none }', 'C.memset(allocation, 0, geometry.captures_offset)',
		'return SyncobjWaitBuffer{ allocation: allocation,', 'handles: unsafe { &u32(allocation) }',
		'objects: unsafe { &voidptr(u64(allocation) + geometry.objects_offset) }'], 'Vinix zeroed handle/object prefix ownership')!
	require(allocate.count('memory.malloc_packed_fallible(') == 1 && !allocate.contains('captures:'),
		'RESET owner must not register or allocate captures')!
	replace := section(sync, 'pub fn replace_fence(', 'pub fn get_fence(', 'Vinix binary replacement')!
	require_order(replace, ['o.lock.acquire()', 'o.fence = unsafe { fence }',
		'o.timeline_points.clear()', 'o.publish_captures_locked(fence)', 'o.lock.release()'],
		'Vinix binary replacement discards timeline lookup under the object lock')!
	require(!replace.contains('memory.free') && !replace.contains('signal('), 'Binary replacement must retain captured fence metadata')!
	ref_fields := section(header, 'struct drm_syncobj_array {', '};', 'Linux RESET array')!
	require_order(ref_fields, ['__u64 handles;', '__u32 count_handles;', '__u32 pad;'], 'Linux RESET wire fields')!
	macro := header.split_into_lines().filter(it.starts_with('#define DRM_IOCTL_SYNCOBJ_RESET'))
	require(macro.len == 1 && macro[0].contains('DRM_IOWR(0xC4, struct drm_syncobj_array)'), 'Linux RESET request encoding changed')!
	ref_reset := section(reference, 'drm_syncobj_reset_ioctl(', 'drm_syncobj_signal_ioctl(', 'Linux RESET')!
	require_order(ref_reset, ['if (args->pad != 0)', 'return -EINVAL', 'if (args->count_handles == 0)',
		'return -EINVAL', 'drm_syncobj_array_find(', 'if (ret < 0)', 'return ret',
		'for (i = 0; i < args->count_handles; i++)', 'drm_syncobj_replace_fence(syncobjs[i], NULL)',
		'drm_syncobj_array_free(syncobjs, args->count_handles)', 'return 0'], 'Linux validation before sequential reset')!
	ref_replace := section(reference, 'void drm_syncobj_replace_fence(', 'EXPORT_SYMBOL(drm_syncobj_replace_fence)', 'Linux binary replacement')!
	require_order(ref_replace, ['dma_fence_get(fence)', 'spin_lock(&syncobj->lock)',
		'rcu_assign_pointer(syncobj->fence, fence)', 'spin_unlock(&syncobj->lock)',
		'dma_fence_put(old_fence)'], 'Linux replaces the timeline root while existing fence references survive')!
}
