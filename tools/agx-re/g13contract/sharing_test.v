module g13contract

import g13layout
import os

fn test_sharing_guards_reject_snapshots_wrong_types_and_double_release() {
	repo := g13layout.repo_root()
	drm := os.read_file(repo + '/kernel/drm/drm.v')!
	transport := os.read_file(repo + '/kernel/drm/syncobj_fd.v')!
	objects := os.read_file(repo + '/kernel/drm/syncobj/syncobj.v')!
	reference := 'int drm_syncobj_get_fd(\nget_unused_fd_flags(O_CLOEXEC);\nanon_inode_getfile("syncobj_file",\n' +
		'&drm_syncobj_file_fops);\ndrm_syncobj_get(syncobj);\nfd_install(fd, file);\nEXPORT_SYMBOL(drm_syncobj_get_fd)\n' +
		'static int drm_syncobj_fd_to_handle(\nfd_file(f)->f_op != &drm_syncobj_file_fops;\nreturn -EINVAL;\n' +
		'syncobj = fd_file(f)->private_data;\ndrm_syncobj_get(syncobj);\n' +
		'xa_alloc(&file_private->syncobj_xa, handle, syncobj, xa_limit_32b,\nstatic int drm_syncobj_import_sync_file_fence(\n' +
		'fence = sync_file_get_fence(fd);\nif (!fence) return -EINVAL;\n' +
		'syncobj = drm_syncobj_find(file_private, handle);\nif (!syncobj) return -ENOENT;\n' +
		'if (point) {\nchain = dma_fence_chain_alloc();\nif (!chain) return -ENOMEM;\n' +
		'drm_syncobj_add_point(syncobj, chain, fence, point);\n} else {\n' +
		'drm_syncobj_replace_fence(syncobj, fence);\nstatic int drm_syncobj_export_sync_file('
	check_sharing_contract(drm, transport, objects, reference)!
	for token in ['if request.flags & ioctl.drm_syncobj_handle_to_fd_export_sync_file == 0',
		'create_syncobj_fd(obj)', 'syncobj.import_syncobj(u64(handle), obj)',
		'find_syncobj_fence(u64(handle), request.handle, point, 0)', 'syncobj.release_chain_reservation(chain)'] {
		if _ := check_sharing_contract(drm.replace(token, ''), transport, objects, reference) { assert false, token }
	}
	for token in ['resource.o_cloexec', 'if mut res is SyncobjResource', 'defer { fd.unref() }',
		'memory.malloc_packed_fallible(sizeof(resource.Resource))', 'if box == unsafe { nil }', 'memory.free(allocation)'] {
		if _ := check_sharing_contract(drm, transport.replace(token, ''), objects, reference) { assert false, token }
	}
	if _ := check_sharing_contract(drm, transport.replace('mut res := wrapper.box', 'memory.free(allocation)\nmut res := wrapper.box'), objects, reference) { assert false }
	if _ := check_sharing_contract(drm, transport, objects.replace('object: obj, allocated: true', 'object: nil, allocated: true'), reference) { assert false }
	if _ := check_sharing_contract(drm, transport, objects, reference.replace('syncobj = fd_file(f)->private_data', '')) { assert false }
	for token in ['sync_file_fence_from_fd(request.fd) or { return -22 }',
		'syncobj.lookup_referenced(u64(handle), request.handle) or { return -2 }', 'syncobj.replace_fence(obj, fence)'] {
		if _ := check_sharing_contract(drm.replace(token, ''), transport, objects, reference) { assert false, token }
	}
	old_order := drm.replace('fence := sync_file_fence_from_fd(request.fd) or { return -22 }\n' +
		'\tobj := syncobj.lookup_referenced(u64(handle), request.handle) or { return -2 }',
		'obj := syncobj.lookup_referenced(u64(handle), request.handle) or { return -2 }\n' +
		'\tfence := sync_file_fence_from_fd(request.fd) or { return -22 }')
	assert old_order != drm
	if _ := check_sharing_contract(old_order, transport, objects, reference) { assert false }
	if _ := check_sharing_contract(drm, transport, objects, reference.replace('if (!fence) return -EINVAL;', '')) { assert false }
	if _ := check_sharing_contract(drm, transport, objects, reference.replace('if (!syncobj) return -ENOENT;', '')) { assert false }
}
