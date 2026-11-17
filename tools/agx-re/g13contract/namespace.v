// SPDX-License-Identifier: GPL-2.0-or-later
module g13contract

fn check_namespace_contract(objects string, reference string) ! {
	require(!objects.contains('syncobj_table') && !objects.contains('syncobj_max_objects'),
		'Syncobj namespaces must not retain a fixed global or per-file object cap')!
	require(objects.contains('syncobj_head &SyncobjHandle = unsafe { nil }')
		&& objects.contains('namespace SyncobjHandle'), 'Missing independent handle ownership')!
	next := section(objects, 'fn next_namespace_handle(', '// Allocate a sync object', 'Vinix 32-bit handle successor')!
	require_order(next, ['if handle == ~u32(0) { return none }', 'return handle + 1'], 'Vinix non-wrapping full handle range')!
	create := section(objects, 'fn insert_handle(', '// Look up a sync object', 'Vinix sorted namespace insertion')!
	require_order(create, ['syncobj_lock.acquire()', 'defer {', 'syncobj_lock.release()',
		'mut previous := &SyncobjHandle(unsafe { nil })', 'mut cursor := unsafe { syncobj_head }',
		'cursor.owner < owner', 'previous = unsafe { cursor }', 'cursor = unsafe { cursor.next }',
		'mut handle := u32(1)', 'cursor.owner == owner', 'if cursor.handle > handle { break }',
		'next_namespace_handle(handle) or { return none }', 'e.handle = handle',
		'if !e.allocated { unsafe { e.object.handle = handle } }', 'retain_syncobj(e.object)', 'e.next = unsafe { cursor }',
		'syncobj_head = e', 'previous.next = e'], 'Vinix lowest-gap insertion under namespace lock')!
	lookup := section(objects, 'pub fn lookup(', '// Destroy one object', 'Vinix namespace lookup')!
	require_order(lookup, ['if owner == 0 || handle == 0', 'syncobj_lock.acquire()',
		'defer { syncobj_lock.release() }', 'mut cursor := unsafe { syncobj_head }',
		'cursor.owner > owner', 'cursor.owner == owner && cursor.handle == handle', 'if referenced { retain_syncobj(cursor.object) }',
		'return unsafe { cursor.object }', 'cursor = unsafe { cursor.next }'], 'Vinix uncapped shared identity lookup')!
	destroy := section(objects, 'pub fn destroy(', '// Final DRM-file release', 'Vinix exact-object removal')!
	require_order(destroy, ['syncobj_lock.acquire()',
		'cursor.owner == owner && cursor.handle == handle', 'syncobj_head = unsafe { cursor.next }',
		'previous.next = cursor.next', 'cursor.next = nil', 'removed = unsafe { cursor }',
		'syncobj_lock.release()', 'release_syncobj(removed.object)', 'if removed.allocated { memory.free(voidptr(removed)) }', 'return true'],
		'Vinix unlink before freeing only allocated links')!
	release := section(objects, 'pub fn destroy_owner(', '// Atomically replace', 'Vinix namespace close')!
	require_order(release, ['syncobj_lock.acquire()', 'cursor.owner < owner', 'cursor.owner == owner',
		'next := unsafe { cursor.next }', 'syncobj_head = unsafe { next }',
		'previous.next = next', 'cursor.next = retired',
		'retired = unsafe { cursor }', 'cursor = unsafe { next }',
		'syncobj_lock.release()', 'next := unsafe { retired.next }', 'retired.next = nil',
		'release_syncobj(retired.object)', 'if retired.allocated { memory.free(voidptr(retired)) }',
		'retired = unsafe { next }'], 'Vinix owner-block detach before link retirement')!
	require(destroy.count('memory.free(') == 1 && release.count('memory.free(') == 1
		&& !destroy.contains('memory.free(voidptr(cursor.object))') && !release.contains('memory.free(voidptr(cursor.object))'),
		'Unlink must preserve captured object/fence metadata')!
	open := section(reference, 'drm_syncobj_open(', '/**\n * drm_syncobj_release', 'Linux per-file handle namespace')!
	require(open.contains('xa_init_flags(&file_private->syncobj_xa, XA_FLAGS_ALLOC1)'), 'Linux nonzero handle policy changed')!
	get := section(reference, 'int drm_syncobj_get_handle(', 'EXPORT_SYMBOL(drm_syncobj_get_handle)', 'Linux handle allocation')!
	require(get.contains('xa_alloc(&file_private->syncobj_xa, handle, syncobj, xa_limit_32b,'), 'Linux 32-bit namespace limit changed')!
	find := section(reference, 'struct drm_syncobj *drm_syncobj_find(', 'EXPORT_SYMBOL(drm_syncobj_find)', 'Linux owner-scoped lookup')!
	require_order(find, ['xa_lock(&file_private->syncobj_xa)', 'xa_load(&file_private->syncobj_xa, handle)',
		'drm_syncobj_get(syncobj)', 'xa_unlock(&file_private->syncobj_xa)'], 'Linux referenced per-file lookup')!
}
