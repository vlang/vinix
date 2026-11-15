module g13contract

import g13layout
import os

fn test_namespace_guards_reject_fixed_caps_wrap_and_stale_links() {
	objects := os.read_file(g13layout.repo_root() + '/kernel/drm/syncobj/syncobj.v')!
	reference := 'drm_syncobj_open(\nxa_init_flags(&file_private->syncobj_xa, XA_FLAGS_ALLOC1);\n' +
		'/**\n * drm_syncobj_release\nint drm_syncobj_get_handle(\n' +
		'xa_alloc(&file_private->syncobj_xa, handle, syncobj, xa_limit_32b,\n' +
		'EXPORT_SYMBOL(drm_syncobj_get_handle)\nstruct drm_syncobj *drm_syncobj_find(\n' +
		'xa_lock(&file_private->syncobj_xa);\nxa_load(&file_private->syncobj_xa, handle);\n' +
		'drm_syncobj_get(syncobj);\nxa_unlock(&file_private->syncobj_xa);\nEXPORT_SYMBOL(drm_syncobj_find)'
	check_namespace_contract(objects, reference)!
	for token in ['if handle == ~u32(0) { return none }', 'if cursor.handle > handle { break }',
		'obj.namespace_next = unsafe { cursor }', 'previous.namespace_next = obj',
		'previous.namespace_next = cursor.namespace_next', 'cursor.namespace_next = nil',
		'previous.namespace_next = next'] {
		if _ := check_namespace_contract(objects.replace(token, ''), reference) { assert false, token }
	}
	if _ := check_namespace_contract(objects + '\nconst syncobj_max_objects = u32(1024)\n', reference) { assert false }
	if _ := check_namespace_contract(objects, reference.replace('XA_FLAGS_ALLOC1', 'XA_FLAGS_ALLOC')) { assert false }
	if _ := check_namespace_contract(objects, reference.replace('xa_limit_32b', 'xa_limit_16b')) { assert false }
}
