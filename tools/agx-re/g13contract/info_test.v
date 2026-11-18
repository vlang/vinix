module g13contract

import g13layout

fn test_info_guard_rejects_layout_copy_order_status_provenance_and_cleanup_drift() {
	repo := g13layout.repo_root()
	drm := read(repo + '/kernel/drm/drm.v')!
	uapi := read(repo + '/kernel/drm/ioctl/ioctl.v')!
	implementation := read(repo + '/kernel/drm/sync_file_info.v')!
	snapshot := read(repo + '/kernel/drm/syncobj/info.v')!
	stub := read(repo + '/kernel/drm/syncobj/stub.v')!
	check_sync_file_info_contract(drm, uapi, implementation, snapshot, stub)!
	for token in ['defer { memory.free(allocation) }', 'if info.num_fences == 0', 'info.num_fences = count',
		'file_name[offset] = 0', 'mut digits := [20]u8{}', 'u64(-(i64(info.seqno) + 1)) + 1',
		'C.memset(allocation, 0, bytes)', 'if info.num_fences < count { return -22 }',
		'cursor = syncobj.unwrap_next(iterator)', 'if info.status > 0 { info.status = detail.status }',
		'usercopy.copy_to_user(info.sync_fence_info, details, bytes)'] {
		if _ := check_sync_file_info_contract(drm, uapi, implementation.replace(token, ''), snapshot, stub) { assert false, token }
	}
	for token in ['f.lock.acquire()', 'f.lock.release()', 'if !f.signaled { 0 }', 'f.private_stub', 'f.queue_context != 0'] {
		if _ := check_sync_file_info_contract(drm, uapi, implementation, snapshot.replace(token, ''), stub) { assert false, token }
	}
	for token in ['sync_ioc_file_info = u32(0xc0383e04)', 'num_fences u32', 'timestamp_ns u64'] {
		if _ := check_sync_file_info_contract(drm, uapi.replace(token, ''), implementation, snapshot, stub) { assert false, token }
	}
	if _ := check_sync_file_info_contract(drm.replace('sync_file_info_ioctl(this.fence, u64(argp), unsafe { &this.name[0] })', ''), uapi, implementation, snapshot, stub) { assert false }
	if _ := check_sync_file_info_contract(drm, uapi, implementation, snapshot, stub.replace('fence.private_stub = true', '')) { assert false }
}
