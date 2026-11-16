// SPDX-License-Identifier: GPL-2.0-or-later
module g13contract

fn check_sharing_contract(drm string, transport string, objects string, reference string) ! {
	export := section(drm, 'fn ioctl_syncobj_handle_to_fd(', 'fn ioctl_syncobj_fd_to_handle(', 'Vinix syncobj export')!
	require_order(export, ['request.flags & ~ioctl.drm_syncobj_handle_to_fd_export_sync_file',
		'syncobj.lookup(u64(handle), request.handle)', 'if request.flags == 0', 'create_syncobj_fd(obj)',
		'syncobj.get_fence(obj)', 'create_sync_file_fd(fence)'], 'Opaque export must transport the object, including empty objects')!
	importer := section(drm, 'fn ioctl_syncobj_fd_to_handle(', 'fn ioctl_syncobj_wait(', 'Vinix syncobj import')!
	require_order(importer, ['request.flags & ~ioctl.drm_syncobj_fd_to_handle_import_sync_file',
		'if request.flags == 0', 'syncobj_from_fd(request.fd) or { return -22 }',
		'request.handle = syncobj.import_syncobj(u64(handle), obj) or { return -12 }', 'return 0',
		'sync_file_fence_from_fd(request.fd) or { return -22 }',
		'syncobj.lookup(u64(handle), request.handle) or { return -2 }', 'syncobj.replace_fence(obj, fence)'],
		'Opaque import creates a handle while sync-file import replaces a fence')!
	link := section(objects, 'pub fn import_syncobj(', '// Prepared entries', 'Vinix alias ownership')!
	require_order(link, ['if owner == 0 || obj == unsafe { nil }',
		'memory.malloc_packed_fallible(sizeof(SyncobjHandle))', 'if allocation == unsafe { nil } { return none }',
		'*entry = SyncobjHandle{ owner: owner, object: obj, allocated: true }', 'insert_handle(entry) or {',
		'memory.free(allocation)', 'return none'], 'Fallible independent name for the same object')!
	require(!link.contains('new_syncobj(') && !link.contains('get_fence(') && !link.contains('replace_fence('),
		'Import must preserve mutable identity instead of cloning a fence')!
	fd := section(transport, 'fn create_syncobj_fd(', 'fn syncobj_from_fd(', 'Vinix opaque descriptor')!
	require_order(fd, ['memory.malloc_packed_fallible(sizeof(SyncobjResource))',
		'if allocation == unsafe { nil }', '*wrapper = SyncobjResource{ object: obj }',
		'memory.malloc_packed_fallible(sizeof(resource.Resource))', 'if box == unsafe { nil }',
		'memory.free(allocation)', '*(&voidptr(&wrapper.box)) = box',
		'*wrapper.box = resource.Resource(wrapper)',
		'file.fdnum_create_from_resource(unsafe { nil }, mut res, resource.o_cloexec, 0, false)'],
		'CLOEXEC transport ownership must pass to the file-layer constructor')!
	require(fd.count('memory.free(') == 1 && !fd.contains('fd.unref('), 'Only private box failure may free the wrapper directly')!
	require_order(transport, ['fn syncobj_from_fd(', 'file.fd_from_fdnum(', 'defer { fd.unref() }',
		'if mut res is SyncobjResource', 'return unsafe { res.object }'], 'Opaque type check while holding descriptor reference')!
	file_export := section(drm, 'pub fn create_sync_file_fd(', '// Resolve only fds', 'Vinix sync-file ownership')!
	require_order(file_export, ['memory.malloc_packed_fallible(sizeof(SyncFileResource))',
		'memory.malloc_packed_fallible(sizeof(resource.Resource))', 'if box == unsafe { nil }',
		'memory.free(allocation)', '*wrapper.box = resource.Resource(wrapper)', 'file.fdnum_create_from_resource('],
		'Sync-file wrapper and box must be fallible before ownership transfer')!
	require(file_export.count('memory.free(') == 1,
		'Sync-file constructor failure must release its wrapper exactly once through the file layer')!
	linux_fd := section(reference, 'int drm_syncobj_get_fd(', 'EXPORT_SYMBOL(drm_syncobj_get_fd)', 'Linux opaque fd')!
	require_order(linux_fd, ['get_unused_fd_flags(O_CLOEXEC)', 'anon_inode_getfile("syncobj_file",',
		'&drm_syncobj_file_fops', 'drm_syncobj_get(syncobj)', 'fd_install(fd, file)'], 'Linux opaque transport')!
	linux_import := section(reference, 'static int drm_syncobj_fd_to_handle(', 'static int drm_syncobj_import_sync_file_fence(', 'Linux identity import')!
	require_order(linux_import, ['fd_file(f)->f_op != &drm_syncobj_file_fops', 'return -EINVAL',
		'syncobj = fd_file(f)->private_data', 'drm_syncobj_get(syncobj)',
		'xa_alloc(&file_private->syncobj_xa, handle, syncobj, xa_limit_32b,'], 'Linux same-object alias import')!
	linux_fence_import := section(reference, 'static int drm_syncobj_import_sync_file_fence(',
		'static int drm_syncobj_export_sync_file(', 'Linux binary fence import validation')!
	require_order(linux_fence_import, ['fence = sync_file_get_fence(fd)', 'if (!fence)', 'return -EINVAL',
		'syncobj = drm_syncobj_find(file_private, handle)', 'if (!syncobj)', 'return -ENOENT',
		'drm_syncobj_replace_fence(syncobj, fence)'], 'Linux fence descriptor before destination lookup and publication')!
}
