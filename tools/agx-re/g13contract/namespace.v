// SPDX-License-Identifier: GPL-2.0-or-later
module g13contract

fn check_namespace_contract(objects string, reference string) ! {
	require(!objects.contains('syncobj_table') && !objects.contains('syncobj_max_objects'),
		'Syncobj namespaces must not retain a fixed global or per-file object cap')!
	require(objects.contains('syncobj_head &SyncObj = unsafe { nil }')
		&& objects.contains('namespace_next &SyncObj = unsafe { nil }'), 'Missing intrusive namespace ownership')!
	next := section(objects, 'fn next_namespace_handle(', '// Allocate a sync object', 'Vinix 32-bit handle successor')!
	require_order(next, ['if handle == ~u32(0) { return none }', 'return handle + 1'], 'Vinix non-wrapping full handle range')!
	create := section(objects, 'pub fn new_syncobj_with_flags(', '// Look up a sync object', 'Vinix sorted namespace insertion')!
	require_order(create, ['syncobj_lock.acquire()', 'defer {', 'syncobj_lock.release()',
		'mut previous := &SyncObj(unsafe { nil })', 'mut cursor := unsafe { syncobj_head }',
		'cursor.owner < owner', 'previous = unsafe { cursor }', 'cursor = unsafe { cursor.namespace_next }',
		'mut handle := u32(1)', 'cursor.owner == owner', 'if cursor.handle > handle { break }',
		'next_namespace_handle(handle) or { return none }', 'obj.handle = handle',
		'obj.namespace_next = unsafe { cursor }', 'published = true', 'syncobj_head = obj',
		'previous.namespace_next = obj'], 'Vinix lowest-gap insertion under namespace lock')!
	lookup := section(objects, 'pub fn lookup(', '// Destroy one object', 'Vinix namespace lookup')!
	require_order(lookup, ['if owner == 0 || handle == 0', 'syncobj_lock.acquire()',
		'defer { syncobj_lock.release() }', 'mut cursor := unsafe { syncobj_head }',
		'cursor.owner > owner', 'cursor.owner == owner && cursor.handle == handle',
		'return unsafe { cursor }', 'cursor = unsafe { cursor.namespace_next }'], 'Vinix uncapped lookup')!
	destroy := section(objects, 'pub fn destroy(', '// Final DRM-file release', 'Vinix exact-object removal')!
	require_order(destroy, ['syncobj_lock.acquire()', 'defer { syncobj_lock.release() }',
		'cursor.owner == owner && cursor.handle == handle', 'syncobj_head = unsafe { cursor.namespace_next }',
		'previous.namespace_next = cursor.namespace_next', 'cursor.namespace_next = nil', 'return true'], 'Vinix unlink and detach retained identity')!
	release := section(objects, 'pub fn destroy_owner(', '// Atomically replace', 'Vinix namespace close')!
	require_order(release, ['syncobj_lock.acquire()', 'cursor.owner < owner', 'cursor.owner == owner',
		'next := unsafe { cursor.namespace_next }', 'syncobj_head = unsafe { next }',
		'previous.namespace_next = next', 'cursor.namespace_next = nil', 'cursor = unsafe { next }',
		'syncobj_lock.release()'], 'Vinix contiguous owner-block detachment')!
	require(!destroy.contains('memory.free') && !release.contains('memory.free'), 'Unlink must preserve captured object/fence metadata')!
	open := section(reference, 'drm_syncobj_open(', '/**\n * drm_syncobj_release', 'Linux per-file handle namespace')!
	require(open.contains('xa_init_flags(&file_private->syncobj_xa, XA_FLAGS_ALLOC1)'), 'Linux nonzero handle policy changed')!
	get := section(reference, 'int drm_syncobj_get_handle(', 'EXPORT_SYMBOL(drm_syncobj_get_handle)', 'Linux handle allocation')!
	require(get.contains('xa_alloc(&file_private->syncobj_xa, handle, syncobj, xa_limit_32b,'), 'Linux 32-bit namespace limit changed')!
	find := section(reference, 'struct drm_syncobj *drm_syncobj_find(', 'EXPORT_SYMBOL(drm_syncobj_find)', 'Linux owner-scoped lookup')!
	require_order(find, ['xa_lock(&file_private->syncobj_xa)', 'xa_load(&file_private->syncobj_xa, handle)',
		'drm_syncobj_get(syncobj)', 'xa_unlock(&file_private->syncobj_xa)'], 'Linux referenced per-file lookup')!
}
