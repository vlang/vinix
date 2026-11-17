module g13contract

import g13layout

fn test_deadline_guards_reject_wrong_encoding_copy_order_or_side_effects() {
	repo := g13layout.repo_root()
	drm := read(repo + '/kernel/drm/drm.v')!
	uapi := read(repo + '/kernel/drm/ioctl/ioctl.v')!
	implementation := read(repo + '/kernel/drm/sync_file_deadline.v')!
	check_sync_file_deadline_contract(drm, uapi, implementation)!
	for token in ['usercopy.copy_from_user(', 'sizeof(ioctl.SyncSetDeadline)', 'if request.pad != 0 { return -22 }',
		'return -14', 'syncobj.set_deadline(fence, i64(request.deadline_ns))'] {
		if _ := check_sync_file_deadline_contract(drm, uapi, implementation.replace(token, '')) { assert false, token }
	}
	for effect in ['usercopy.copy_to_user(', 'memory.malloc_packed_fallible(', 'syncobj.signal(', 'sched.reschedule('] {
		if _ := check_sync_file_deadline_contract(drm, uapi, implementation + effect) { assert false, effect }
	}
	for token in ['sync_ioc_set_deadline = u32(0x40103e05)', 'deadline_ns u64', 'pad u64', 'sizeof(SyncSetDeadline) == 16'] {
		if _ := check_sync_file_deadline_contract(drm, uapi.replace(token, ''), implementation) { assert false, token }
	}
	if _ := check_sync_file_deadline_contract(drm.replace('sync_file_deadline_ioctl(this.fence, u64(argp))', ''), uapi, implementation) { assert false }
}
