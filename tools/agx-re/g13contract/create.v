// SPDX-License-Identifier: GPL-2.0-or-later
module g13contract

fn check_create_contract(drm string, objects string, reference string) ! {
	handler := section(drm, 'fn ioctl_syncobj_create(', 'fn create_prime_fd(', 'Vinix CREATE')!
	require_order(handler, ['request.flags & ~ioctl.drm_syncobj_create_signaled', 'return -22',
		'syncobj.new_syncobj_with_flags(u64(handle),',
		'request.flags & ioctl.drm_syncobj_create_signaled != 0) or { return -12 }',
		'request.handle = obj.handle', 'return 0'], 'Vinix flags and fallible initialized creation before output')!
	require(!handler.contains('syncobj.destroy(') && !handler.contains('syncobj.replace_fence('),
		'CREATE must neither roll back by numeric handle nor initialize after publication')!
	wrapper := section(objects, 'pub fn new_syncobj(owner u64)', '// Complete private initialization', 'Vinix legacy empty creation')!
	require(wrapper.contains('return new_syncobj_with_flags(owner, false)'), 'Legacy creation must remain empty')!
	create := section(objects, 'pub fn new_syncobj_with_flags(', '// Look up a sync object', 'Vinix private creation')!
	require_order(create, ['if owner == 0', 'return none',
		'memory.malloc_packed_fallible(sizeof(SyncObj))', 'if allocation == unsafe { nil } { return none }',
		'&SyncObj(allocation)', '*obj = SyncObj{ owner: owner }', 'mut published := false',
		'defer {', 'if !published {', 'if obj.fence != unsafe { nil } { memory.free(voidptr(obj.fence)) }',
		'memory.free(allocation)', 'if signaled {', 'obj.fence = new_private_stub(now_ns()) or { return none }',
		'syncobj_lock.acquire()', 'defer {', 'syncobj_lock.release()',
		'if slot == syncobj_max_objects', 'return none', 'if handle == 0', 'return none',
		'obj.handle = handle', 'published = true', 'syncobj_table[slot] = obj', 'return obj'],
		'Vinix private initialization, unlocked failure cleanup and complete publication')!
	require(create.count('memory.malloc_packed_fallible(') == 1 && create.count('new_private_stub(') == 1
		&& create.count('published = true') == 1 && create.count('syncobj_table[slot] = obj') == 1
		&& !create.contains('destroy('), 'Creation must transfer ownership only once, without handle rollback')!
	ref_create := section(reference, 'int drm_syncobj_create(', 'EXPORT_SYMBOL(drm_syncobj_create)', 'Linux private creation')!
	require_order(ref_create, ['kzalloc_obj(struct drm_syncobj)', 'if (!syncobj)', 'return -ENOMEM',
		'if (flags & DRM_SYNCOBJ_CREATE_SIGNALED)', 'drm_syncobj_assign_null_handle(syncobj)',
		'if (ret < 0)', 'drm_syncobj_put(syncobj)', 'return ret', '*out_syncobj = syncobj', 'return 0'],
		'Linux fallible initial completion before returning the private object')!
	ref_handle := section(reference, 'static int drm_syncobj_create_as_handle(', 'static int drm_syncobj_destroy(', 'Linux handle publication')!
	require_order(ref_handle, ['drm_syncobj_create(&syncobj, flags, NULL)', 'if (ret)', 'return ret',
		'drm_syncobj_get_handle(file_private, syncobj, handle)', 'drm_syncobj_put(syncobj)', 'return ret'],
		'Linux object creation before handle installation')!
}
