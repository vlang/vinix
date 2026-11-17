// SPDX-License-Identifier: GPL-2.0-or-later
module drm

import drm.ioctl
import drm.syncobj
import memory
import proc
import sched
import usercopy

fn make_deadline_fence() &syncobj.DmaFence {
	context := syncobj.new_queue_context() or { panic('deadline queue context') }
	return remember_fence(syncobj.new_queue_fence(7, 1, context))
}

fn expect_fence_deadline(fence &syncobj.DmaFence, expected i64) {
	assert (syncobj.deadline_for_checks(fence) or { panic('missing captured fence deadline') }) == expected
}

fn expect_no_fence_deadline(fence &syncobj.DmaFence) {
	if _ := syncobj.deadline_for_checks(fence) { assert false, 'unexpected fence deadline' }
}

fn check_binary_deadlines() {
	proc.reset()
	sched.reset(unsafe { nil })
	obj := make_object(0)
	fence := make_deadline_fence()
	syncobj.replace_fence(obj, fence)
	completed := make_object(ioctl.drm_syncobj_create_signaled)
	mut handles := [obj.handle, completed.handle]!
	address := unsafe { u64(&handles[0]) }
	usercopy.allow(address, sizeof(handles))
	mut request := ioctl.DrmSyncobjWait{handles: address, count_handles: 2}
	assert ioctl_syncobj_wait(voidptr(11), unsafe { &request }) == 0
	request.flags = ioctl.drm_syncobj_wait_deadline
	assert ioctl_syncobj_wait(voidptr(11), unsafe { &request }) == 0
	expect_no_fence_deadline(fence)
	request.flags |= ioctl.drm_syncobj_wait_all
	assert ioctl_syncobj_wait(voidptr(11), unsafe { &request }) == -62
	expect_fence_deadline(fence, 0)
	request.deadline_nsec = u64(1) << 63
	assert ioctl_syncobj_wait(voidptr(11), unsafe { &request }) == -62
	request.deadline_nsec = ~u64(0)
	assert ioctl_syncobj_wait(voidptr(11), unsafe { &request }) == -62
	expect_fence_deadline(fence, i64(u64(1) << 63))
	expect_no_fence_deadline(current(completed))
	assert sched.polls == 0 && !syncobj.is_signaled(fence)

	// The one-shot hint pass happens after arming and before the first sleep.
	// A submission captured by the scheduler later still satisfies the wait.
	wait_fixture_target = make_object(0)
	wait_fixture_original = make_deadline_fence()
	wait_fixture_replacement = make_fence()
	handles[0] = wait_fixture_target.handle
	request.count_handles = 1
	request.flags = ioctl.drm_syncobj_wait_for_submit | ioctl.drm_syncobj_wait_deadline
	request.timeout_nsec = 8000
	wait_fixture_mode = 3
	sched.reset(scripted)
	assert ioctl_syncobj_wait(voidptr(11), unsafe { &request }) == 0
	assert sched.polls == 3
	expect_no_fence_deadline(wait_fixture_original)
	clear()
}

fn check_timeline_deadlines() {
	memory.check_before_free(unsafe { nil })
	sched.reset(unsafe { nil })
	obj := make_object(0)
	first := make_deadline_fence()
	later := make_deadline_fence()
	first_chain := remember_fence(syncobj.reserve_chain() or { panic('first deadline point') })
	later_chain := remember_fence(syncobj.reserve_chain() or { panic('later deadline point') })
	assert syncobj.add_chain_point(obj, first_chain, first, 5)
	assert syncobj.add_chain_point(obj, later_chain, later, 10)
	empty := make_object(0)
	mut input := TimelineWaitInput{handles: [4096]u32{init: obj.handle}, points: [4096]u64{init: 5}}
	input.handles[1] = empty.handle
	mut request := tw_request(unsafe { &input }, 2, ioctl.drm_syncobj_wait_deadline, 0)
	assert ioctl_syncobj_timeline_wait(voidptr(11), unsafe { &request }) == -22
	expect_no_fence_deadline(first)
	request.flags |= ioctl.drm_syncobj_wait_available
	assert ioctl_syncobj_timeline_wait(voidptr(11), unsafe { &request }) == 0
	expect_no_fence_deadline(first)
	request.flags |= ioctl.drm_syncobj_wait_all
	request.deadline_nsec = 42
	assert ioctl_syncobj_timeline_wait(voidptr(11), unsafe { &request }) == -62
	expect_fence_deadline(first, 42)
	expect_no_fence_deadline(later)
	assert !syncobj.is_signaled(first) && sched.polls == 0
	syncobj.signal(first)
	syncobj.signal(later)
	clear()
}

fn check_nested_deadlines() {
	source := make_object(0)
	first := make_deadline_fence()
	second := make_deadline_fence()
	a := remember_fence(syncobj.reserve_chain() or { panic('chain A') })
	b := remember_fence(syncobj.reserve_chain() or { panic('chain B') })
	assert syncobj.add_chain_point(source, a, first, 5)
	assert syncobj.add_chain_point(source, b, second, 10)
	array := syncobj.unwrap_merge(b) or { panic('deadline array') }

	target := make_object(0)
	mut payload := unsafe { array }
	mut nodes := [2048]&syncobj.DmaFence{}
	for index in 0 .. nodes.len {
		node := syncobj.reserve_chain() or { panic('nested deadline chain') }
		assert syncobj.add_chain_point(target, node, payload, u64(index) + 1)
		nodes[index] = node
		payload = unsafe { node }
	}
	attempts := memory.attempts()
	syncobj.overlap_deadline_drain_for_checks(payload, 30, -50)
	assert memory.attempts() == attempts
	expect_fence_deadline(first, -50)
	expect_fence_deadline(second, -50)
	assert !syncobj.is_signaled(payload)
	syncobj.signal(first)
	syncobj.set_deadline(payload, -100)
	expect_fence_deadline(first, -50)
	expect_fence_deadline(second, -100)
	syncobj.signal(second)
	assert syncobj.is_signaled(payload)
	syncobj.replace_fence(target, unsafe { nil })
	for index in 0 .. nodes.len { memory.free(voidptr(nodes[index])) }
	syncobj.dispose_merged_for_checks(array)
	clear()
	assert memory.outstanding() == 0
}
