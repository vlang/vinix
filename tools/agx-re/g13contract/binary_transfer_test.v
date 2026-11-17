// SPDX-License-Identifier: GPL-2.0-or-later
module g13contract

import g13layout

fn check_binary_transfer(drm string, wire string, transfer string, lookup string) ! {
	require(integer_constant(wire, 'drm_ioctl_syncobj_transfer', 'TRANSFER opcode')! == 0xcc, 'TRANSFER opcode')!
	require_order(drm.all_after('fn common_ioctl_layout('), ['ioctl.drm_ioctl_syncobj_transfer {',
		'size: u32(sizeof(ioctl.DrmSyncobjTransfer)), direction: ioctl_write | ioctl_read'], 'TRANSFER wire layout')!
	require_order(drm.all_after('fn core_ioctl('), ['ioctl.drm_ioctl_syncobj_transfer {', 'return ioctl_syncobj_transfer(handle, data)'], 'TRANSFER dispatch')!
	require_order(transfer, ['request.pad != 0', 'request.dst_point != 0 { return -95 }',
		'destination := syncobj.lookup(', 'source := find_syncobj_fence(', 'if source.code != 0',
		'syncobj.replace_fence(destination, source.fence)'], 'Binary transfer validates before publication and preserves destination identity')!
	require_order(lookup, ['object := syncobj.lookup(', 'flags & ~ioctl.drm_syncobj_wait_for_submit',
		'mut capture := unsafe { &syncobj.TimelineCapture(C.__builtin_alloca(sizeof(syncobj.TimelineCapture))) }',
		'unsafe { *capture = syncobj.TimelineCapture{} }', 'defer { syncobj.release_timeline_capture(capture) }',
		'syncobj.prepare_timeline_capture(', 'syncobj.captured_timeline_fence(', 'syncobj.arm_timeline_capture(',
		'submit_started_ns := syncobj.now_ns()', 'for {', 'syncobj.captured_timeline_fence(',
		'u64(5_000_000_000)', 'proc.pending_signals(', 'sched.reschedule()'], 'Source lookup takes availability snapshots, detaches stack borrow, then waits with bounded timeout')!
	require(lookup.count('syncobj.shared_timeline_stub()') == 2, 'Retired prefixes must supply a stable completion')!
	for token in ['memory.', 'new_fence(', 'syncobj.wait(', 'syncobj.is_signaled('] {
		require(!lookup.contains(token) && !transfer.contains(token), 'Transfer availability path must not allocate or wait for completion: ' + token)!
	}
}

fn test_binary_transfer_order_stack_lifetime_and_availability() {
	repo := g13layout.repo_root()
	drm := read(repo + '/kernel/drm/drm.v')!; wire := read(repo + '/kernel/drm/ioctl/ioctl.v')!
	transfer := read(repo + '/kernel/drm/syncobj_transfer.v')!; lookup := read(repo + '/kernel/drm/syncobj_find.v')!
	check_binary_transfer(drm, wire, transfer, lookup)!
	for token in ['defer { syncobj.release_timeline_capture(capture) }', 'syncobj.arm_timeline_capture(',
		'flags & ~ioctl.drm_syncobj_wait_for_submit', 'syncobj.shared_timeline_stub()'] {
		if _ := check_binary_transfer(drm, wire, transfer, lookup.replace(token, '')) { assert false, token }
	}
	for token in ['request.pad != 0', 'request.dst_point != 0 { return -95 }', 'if source.code != 0'] {
		if _ := check_binary_transfer(drm, wire, transfer.replace(token, ''), lookup) { assert false, token }
	}
}
