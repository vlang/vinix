module g13contract

import g13layout
import os

fn test_creation_guards_reject_early_publication_and_unsafe_failure_cleanup() {
	repo := g13layout.repo_root()
	drm := os.read_file(repo + '/kernel/drm/drm.v')!
	objects := os.read_file(repo + '/kernel/drm/syncobj/syncobj.v')!
	reference := 'int drm_syncobj_create(\nkzalloc_obj(struct drm_syncobj);\nif (!syncobj) return -ENOMEM;\n' +
		'if (flags & DRM_SYNCOBJ_CREATE_SIGNALED)\ndrm_syncobj_assign_null_handle(syncobj);\n' +
		'if (ret < 0) { drm_syncobj_put(syncobj); return ret; }\n*out_syncobj = syncobj;\nreturn 0;\n' +
		'EXPORT_SYMBOL(drm_syncobj_create)\nstatic int drm_syncobj_create_as_handle(\n' +
		'drm_syncobj_create(&syncobj, flags, NULL);\nif (ret) return ret;\n' +
		'drm_syncobj_get_handle(file_private, syncobj, handle);\ndrm_syncobj_put(syncobj);\nreturn ret;\n' +
		'static int drm_syncobj_destroy('
	check_create_contract(drm, objects, reference)!
	for token in ['memory.malloc_packed_fallible(sizeof(SyncObj))', 'if !published {',
		'memory.free(voidptr(obj.fence))', 'memory.free(allocation)',
		'obj.fence = new_private_stub(now_ns()) or { return none }', 'syncobj_lock.release()',
		'obj.handle = handle', 'published = true'] {
		if _ := check_create_contract(drm, objects.replace(token, ''), reference) { assert false, token }
	}
	if _ := check_create_contract(drm, objects.replace('published = true', 'destroy(owner, handle)\npublished = true'), reference) { assert false }
	if _ := check_create_contract(drm, objects.replace('obj.handle = handle', 'syncobj_table[slot] = obj\nobj.handle = handle'), reference) { assert false }
	if _ := check_create_contract(drm.replace('request.handle = obj.handle', ''), objects, reference) { assert false }
	if _ := check_create_contract(drm, objects, reference.replace('drm_syncobj_create(&syncobj, flags, NULL);', '')) { assert false }
}
