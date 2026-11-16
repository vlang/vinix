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
		'xa_alloc(&file_private->syncobj_xa, handle, syncobj, xa_limit_32b,\nstatic int drm_syncobj_import_sync_file_fence('
	check_sharing_contract(drm, transport, objects, reference)!
	for token in ['if request.flags == 0', 'create_syncobj_fd(obj)', 'syncobj.import_syncobj(u64(handle), obj)'] {
		if _ := check_sharing_contract(drm.replace(token, ''), transport, objects, reference) { assert false, token }
	}
	for token in ['resource.o_cloexec', 'if mut res is SyncobjResource', 'defer { fd.unref() }',
		'memory.malloc_packed_fallible(sizeof(resource.Resource))', 'if box == unsafe { nil }', 'memory.free(allocation)'] {
		if _ := check_sharing_contract(drm, transport.replace(token, ''), objects, reference) { assert false, token }
	}
	if _ := check_sharing_contract(drm, transport.replace('mut res := wrapper.box', 'memory.free(allocation)\nmut res := wrapper.box'), objects, reference) { assert false }
	if _ := check_sharing_contract(drm, transport, objects.replace('object: obj, allocated: true', 'object: nil, allocated: true'), reference) { assert false }
	if _ := check_sharing_contract(drm, transport, objects, reference.replace('syncobj = fd_file(f)->private_data', '')) { assert false }
}
