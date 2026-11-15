module g13contract

import g13layout
import os

fn test_reset_guards_reject_missing_snapshot_cleanup_and_wire_drift() {
	repo := g13layout.repo_root()
	drm := os.read_file(repo + '/kernel/drm/drm.v')!
	wire := os.read_file(repo + '/kernel/drm/ioctl/ioctl.v')!
	storage := os.read_file(repo + '/kernel/drm/wait_storage.v')!
	sync := os.read_file(repo + '/kernel/drm/syncobj/syncobj.v')!
	reference := 'drm_syncobj_reset_ioctl(\nif (args->pad != 0) return -EINVAL;\n' +
		'if (args->count_handles == 0) return -EINVAL;\ndrm_syncobj_array_find();\n' +
		'if (ret < 0) return ret;\nfor (i = 0; i < args->count_handles; i++)\n' +
		'drm_syncobj_replace_fence(syncobjs[i], NULL);\ndrm_syncobj_array_free(syncobjs, args->count_handles);\nreturn 0;\n' +
		'drm_syncobj_signal_ioctl(\nvoid drm_syncobj_replace_fence(\ndma_fence_get(fence);\n' +
		'spin_lock(&syncobj->lock);\nrcu_assign_pointer(syncobj->fence, fence);\n' +
		'spin_unlock(&syncobj->lock);\ndma_fence_put(old_fence);\nEXPORT_SYMBOL(drm_syncobj_replace_fence)'
	header := 'struct drm_syncobj_array {\n__u64 handles;\n__u32 count_handles;\n__u32 pad;\n};\n' +
		'#define DRM_IOCTL_SYNCOBJ_RESET DRM_IOWR(0xC4, struct drm_syncobj_array)\n'
	check_reset_contract(drm, wire, storage, sync, reference, header)!
	for token in ['request.pad != 0 ||', 'defer { buffer.free_owned() }',
		'buffer.objects[i] = voidptr(object)', 'return ioctl_syncobj_reset(handle, data)'] {
		if _ := check_reset_contract(drm.replace(token, ''), wire, storage, sync, reference, header) { assert false, token }
	}
	for token in ['memory.malloc_packed_fallible(geometry.captures_offset)', 'C.memset(allocation, 0, geometry.captures_offset)'] {
		if _ := check_reset_contract(drm, wire, storage.replace(token, ''), sync, reference, header) { assert false, token }
	}
	if _ := check_reset_contract(drm, wire.replace('drm_ioctl_syncobj_reset = u32(0xc4)', 'drm_ioctl_syncobj_reset = u32(0xc5)'), storage, sync, reference, header) { assert false }
	if _ := check_reset_contract(drm, wire, storage, sync.replace('o.timeline_points.clear()', ''), reference, header) { assert false }
	if _ := check_reset_contract(drm, wire, storage, sync, reference.replace('drm_syncobj_replace_fence(syncobjs[i], NULL)', ''), header) { assert false }
	if _ := check_reset_contract(drm, wire, storage, sync, reference, header.replace('0xC4', '0xC5')) { assert false }
}
