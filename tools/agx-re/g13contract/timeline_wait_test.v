// SPDX-License-Identifier: GPL-2.0-or-later
module g13contract

import g13layout

fn check_timeline_wait_contract(drm string, wire string, wait string, capture string, object string, chain string) ! {
	require(integer_constant(wire, 'drm_ioctl_syncobj_timeline_wait', 'Timeline WAIT opcode')! == 0xca, 'Timeline WAIT opcode')!
	registration := drm.all_after('fn common_ioctl_layout(').all_after('ioctl.drm_ioctl_syncobj_timeline_wait {').all_before('ioctl.drm_ioctl_syncobj_transfer {')
	require_order(registration, ['size: u32(sizeof(ioctl.DrmSyncobjTimelineWait))',
		'direction: ioctl_write | ioctl_read', 'extensible: true'], 'Timeline WAIT registration')!
	require_order(drm.all_after('fn core_ioctl('), ['ioctl.drm_ioctl_syncobj_timeline_wait {',
		'return ioctl_syncobj_timeline_wait(handle, data)'], 'Timeline WAIT dispatch')!
	require_order(wait, ['if request.flags & ~known != 0', 'if count == 0 { return 0 }',
		'new_syncobj_handle_buffer(count)', 'defer { buffer.free_owned() }', 'usercopy.copy_from_user(buffer.handles',
		'syncobj.lookup(', 'buffer.objects[index] = voidptr(object)', 'points_storage := memory.malloc_packed_fallible(',
		'defer { memory.free(points_storage) }', 'if request.points == 0', 'usercopy.copy_from_user(points_storage',
		'captures_storage := memory.malloc_packed_fallible(', 'defer { memory.free(captures_storage) }',
		'C.memset(captures_storage, 0,', 'remaining--; syncobj.release_timeline_capture(unsafe { &captures[remaining] })',
		'syncobj.prepare_timeline_capture(', 'if ready_count == count ||', 'syncobj.arm_timeline_capture(',
		'if flags & ioctl.drm_syncobj_wait_deadline != 0', 'syncobj.captured_timeline_fence(',
		'syncobj.set_deadline(fence, i64(request.deadline_nsec))',
		'for {', 'syncobj.captured_timeline_fence(', 'request.timeout_nsec <= 0', 'proc.pending_signals(', 'sched.reschedule()'],
		'Timeline WAIT validates snapshots before arming, unlinks before freeing owners and yields with absolute time')!
	require(wait.count('memory.malloc_packed_fallible(') == 2, 'Exactly two explicit table owners')!
	prepare := capture.all_after('pub fn prepare_timeline_capture(').all_before('pub fn arm_timeline_capture(')
	require_order(prepare, ['o.lock.acquire()', 'c.object = unsafe { obj }', 'c.point = point',
		'valid := c.resolve_locked(o.fence) || allow_future', 'o.lock.release()'], 'Initial snapshot under publication lock')!
	require(!prepare.contains('timeline_captures =') && !prepare.contains('c.pending = true'), 'Initial pass must not register future captures')!
	require_order(capture.all_after('pub fn arm_timeline_capture('), ['o.lock.acquire()', '!c.available && !c.pending && !c.resolve_locked(o.fence)',
		'c.next = unsafe { o.timeline_captures }', 'c.pending = true', 'o.timeline_captures = unsafe { capture }', 'o.lock.release()'], 'Atomic recheck and registration')!
	require_order(capture.all_after('pub fn release_timeline_capture('), ['o.lock.acquire()', 'if c.pending', 'o.timeline_captures = unsafe { cursor.next }',
		'previous.next = cursor.next', 'c.object = unsafe { nil }', 'o.lock.release()'], 'Unlink and clear before returning borrowed storage')!
	require(object.contains('timeline_captures &TimelineCapture') && object.contains('o.publish_timeline_captures_locked(fence)'), 'Replacement publishes timeline captures')!
	require(chain.contains('o.publish_timeline_captures_locked(reservation)'), 'Chain publication supplies timeline captures')!
	require(!capture.contains('memory.') && !capture.contains('shared_timeline_stub('), 'Capture storage is borrowed and publication never takes stub/clock locks')!
}

fn test_timeline_wait_cleanup_two_phase_capture_and_publication() {
	repo := g13layout.repo_root()
	drm := read(repo + '/kernel/drm/drm.v')!
	wire := read(repo + '/kernel/drm/ioctl/ioctl.v')!
	wait := read(repo + '/kernel/drm/syncobj_timeline_wait.v')!
	capture := read(repo + '/kernel/drm/syncobj/timeline_capture.v')!
	object := read(repo + '/kernel/drm/syncobj/syncobj.v')!
	chain := read(repo + '/kernel/drm/syncobj/chain.v')!
	check_timeline_wait_contract(drm, wire, wait, capture, object, chain)!
	for token in ['defer { buffer.free_owned() }', 'defer { memory.free(points_storage) }',
		'defer { memory.free(captures_storage) }', 'C.memset(captures_storage, 0,',
		'remaining--; syncobj.release_timeline_capture(unsafe { &captures[remaining] })', 'syncobj.arm_timeline_capture('] {
		if _ := check_timeline_wait_contract(drm, wire, wait.replace(token, ''), capture, object, chain) { assert false, token }
	}
	for token in ['o.lock.acquire()', 'c.pending = true', 'c.object = unsafe { nil }'] {
		if _ := check_timeline_wait_contract(drm, wire, wait, capture.replace(token, ''), object, chain) { assert false, token }
	}
	if _ := check_timeline_wait_contract(drm, wire, wait, capture, object.replace('o.publish_timeline_captures_locked(fence)', ''), chain) { assert false }
	if _ := check_timeline_wait_contract(drm, wire, wait, capture, object, chain.replace('o.publish_timeline_captures_locked(reservation)', '')) { assert false }
}
