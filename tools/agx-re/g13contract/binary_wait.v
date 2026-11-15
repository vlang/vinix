// SPDX-License-Identifier: GPL-2.0-or-later
module g13contract

fn check_binary_wait_contract(local string, reference string) ! {
	create := section(local, 'fn ioctl_syncobj_create(', 'fn create_prime_fd(', 'Vinix binary syncobj creation')!
	require_order(create, ['syncobj.new_syncobj(', 'if request.flags & ioctl.drm_syncobj_create_signaled != 0 {',
		'syncobj.new_fence(', 'syncobj.signal(fence)', 'syncobj.replace_fence(obj, fence)'], 'Vinix empty versus signaled creation')!
	require(create.count('syncobj.new_fence(') == 1, 'Only signaled creation installs a fence')!
	wait := section(local, 'fn ioctl_syncobj_wait(', 'fn core_ioctl(', 'Vinix binary syncobj wait')!
	flags := section(wait, 'known_flags :=', 'if request.count_handles == 0', 'Vinix binary wait flags')!
	require(flags.contains('ioctl.drm_syncobj_wait_all') && flags.contains('ioctl.drm_syncobj_wait_for_submit')
		&& flags.contains('ioctl.drm_syncobj_wait_deadline') && !flags.contains('ioctl.drm_syncobj_wait_available'),
		'Binary waits must reject the timeline-only availability flag')!
	require_order(wait, ['if request.count_handles == 0 { return 0 }', 'usercopy.copy_from_user(',
		'objects[i] = syncobj.lookup(', 'return -2', 'defer {', 'syncobj.release_capture(',
		'if !syncobj.prepare_capture(', 'request.flags & ioctl.drm_syncobj_wait_for_submit != 0',
		'return -22', 'for {', 'syncobj.captured_fence(', 'syncobj.is_signaled(fence)',
		'if ready {', 'request.timeout_nsec <= 0', 'sched.reschedule()'],
		'Vinix upfront snapshots, submission capture and deferred detachment')!
	require(wait.count('usercopy.copy_from_user(') == 1 && !wait.contains('usercopy.read_u32(')
		&& !wait.contains('obj.fence') && !wait.contains('syncobj.get_fence('),
		'Waiting must not reread user handles or current object fences')!
	ref_create := section(reference, 'int drm_syncobj_create(', 'EXPORT_SYMBOL(drm_syncobj_create)', 'Linux syncobj creation')!
	require_order(ref_create, ['kzalloc_obj(struct drm_syncobj)', 'if (flags & DRM_SYNCOBJ_CREATE_SIGNALED)',
		'drm_syncobj_assign_null_handle(syncobj)', 'if (fence)', 'drm_syncobj_replace_fence(syncobj, fence)'], 'Linux empty versus signaled creation')!
	ref_flags := section(reference, 'drm_syncobj_wait_ioctl(', 'drm_syncobj_timeline_wait_ioctl(', 'Linux binary wait ioctl')!
	require_order(ref_flags, ['possible_flags = DRM_SYNCOBJ_WAIT_FLAGS_WAIT_ALL |',
		'DRM_SYNCOBJ_WAIT_FLAGS_WAIT_FOR_SUBMIT |', 'DRM_SYNCOBJ_WAIT_FLAGS_WAIT_DEADLINE;',
		'if (args->flags & ~possible_flags)', 'if (args->count_handles == 0)', 'drm_syncobj_array_find('], 'Linux binary wait flags and empty array')!
	require(!ref_flags.contains('DRM_SYNCOBJ_WAIT_FLAGS_WAIT_AVAILABLE'), 'Linux binary wait availability policy changed')!
	ref_find := section(reference, 'static int drm_syncobj_array_find(', 'static void drm_syncobj_array_free(', 'Linux wait handle snapshot')!
	require_order(ref_find, ['copy_from_user(handles, user_handles', 'syncobjs[i] = drm_syncobj_find(', 'ret = -ENOENT'], 'Linux copied handles and object references')!
	ref_wait := section(reference, 'static signed long drm_syncobj_array_wait_timeout(', '* drm_timeout_abs_to_jiffies', 'Linux wait fence snapshot')!
	require_order(ref_wait, ['fence = drm_syncobj_fence_get(syncobjs[i])',
		'DRM_SYNCOBJ_WAIT_FLAGS_WAIT_FOR_SUBMIT |', 'timeout = -EINVAL',
		'entries[i].fence = fence', 'do {', 'fence = entries[i].fence', 'dma_fence_is_signaled(fence)'], 'Linux stable fence snapshots before waiting')!
}
