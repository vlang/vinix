module g13contract

import g13layout
import os

fn test_signal_guards_reject_old_fence_signaling_shared_stubs_and_lost_oom_prefix() {
	repo := g13layout.repo_root()
	drm := os.read_file(repo + '/kernel/drm/drm.v')!
	wire := os.read_file(repo + '/kernel/drm/ioctl/ioctl.v')!
	stub := os.read_file(repo + '/kernel/drm/syncobj/stub.v')!
	header := '#define DRM_IOCTL_SYNCOBJ_SIGNAL DRM_IOWR(0xC5, struct drm_syncobj_array)\n'
	reference := 'drm_syncobj_signal_ioctl(\nif (args->pad != 0) return -EINVAL;\n' +
		'if (args->count_handles == 0) return -EINVAL;\ndrm_syncobj_array_find();\n' +
		'if (ret < 0) return ret;\nfor (i = 0; i < args->count_handles; i++)\n' +
		'ret = drm_syncobj_assign_null_handle(syncobjs[i]);\nif (ret < 0) break;\n' +
		'drm_syncobj_array_free(syncobjs, args->count_handles);\nreturn ret;\n' +
		'drm_syncobj_timeline_signal_ioctl(\nstatic int drm_syncobj_assign_null_handle(\n' +
		'dma_fence_allocate_private_stub(ktime_get());\nif (!fence) return -ENOMEM;\n' +
		'drm_syncobj_replace_fence(syncobj, fence);\ndma_fence_put(fence);\n/* 5s default'
	fences := 'struct dma_fence *dma_fence_allocate_private_stub(\nkzalloc_obj(*fence);\n' +
		'if (fence == NULL) return NULL;\ndma_fence_init(fence, &dma_fence_stub_ops, NULL, 0, 0);\n' +
		'dma_fence_signal_timestamp(fence, timestamp);\nreturn fence;\nEXPORT_SYMBOL(dma_fence_allocate_private_stub)'
	check_signal_contract(drm, wire, stub, reference, fences, header)!
	for token in ['request.pad != 0 ||', 'defer { buffer.free_owned() }',
		'fence := syncobj.new_private_stub(syncobj.now_ns()) or { return -12 }',
		'buffer.objects[i] = voidptr(object)', 'return ioctl_syncobj_signal(handle, data)'] {
		if _ := check_signal_contract(drm.replace(token, ''), wire, stub, reference, fences, header) { assert false, token }
	}
	for token in ['memory.malloc_packed_fallible(sizeof(DmaFence))', 'if allocation == unsafe { nil } { return none }',
		'timestamp_ns: timestamp_ns', 'katomic.store(mut &fence.signaled, true)'] {
		if _ := check_signal_contract(drm, wire, stub.replace(token, ''), reference, fences, header) { assert false, token }
	}
	if _ := check_signal_contract(drm, wire, stub + '\n__global shared_stub DmaFence\n', reference, fences, header) { assert false }
	if _ := check_signal_contract(drm, wire, stub, reference.replace('break;', 'return 0;'), fences, header) { assert false }
	if _ := check_signal_contract(drm, wire, stub, reference, fences.replace('dma_fence_signal_timestamp(fence, timestamp)', ''), header) { assert false }
	if _ := check_signal_contract(drm, wire, stub, reference, fences, header.replace('0xC5', '0xC4')) { assert false }
}
