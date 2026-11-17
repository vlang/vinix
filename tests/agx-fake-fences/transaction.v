// SPDX-License-Identifier: GPL-2.0-or-later
module fake

import drm.syncobj
import gpu.agx.submission as agxsubmission
import klock
import memory

// Only VM pins and file lock/counter plumbing are modeled. reserve_output's
// body is copied from the production submit transaction, adapting only the
// output array's address expression to this wrapper's borrowed parameter.
struct FakeG17Vm {
mut:
	jobs u32 = 3
	allow bool = true
}
fn (mut vm FakeG17Vm) begin_job() bool {
	if !vm.allow { return false }
	vm.jobs++
	return true
}
fn (mut vm FakeG17Vm) finish_job() { assert vm.jobs > 0; vm.jobs-- }
struct FakeG17File {
mut:
	inflight_jobs u32
	lock klock.Lock
}

fn mark_partial_completion(context voidptr, signal bool) {
	unsafe { *(&bool(context)) = signal }
}

fn check_partial_publication() {
	memory.configure_metadata(sizeof(syncobj.SyncObj), sizeof(syncobj.DmaFence))
	binary := syncobj.new_syncobj(111) or { panic('binary output') }
	timeline := syncobj.new_syncobj(111) or { panic('timeline output') }
	mut previous := syncobj.DmaFence{}
	assert syncobj.add_timeline_point(timeline, 5, unsafe { &previous })
	mut notified := false
	assert syncobj.register_eventfd(binary, 0, false, unsafe { &notified }, mark_partial_completion)
	mut objects := unsafe { [64]&syncobj.SyncObj{} }
	mut points := [64]u64{}
	mut timeline_flags := [64]bool{}
	objects[0] = binary
	objects[1] = timeline
	points[1] = 5
	timeline_flags[1] = true
	outputs := agxsubmission.SyncArray{count: 2, objects: objects, timeline: timeline_flags, timeline_values: points}
	mut file := FakeG17File{}
	mut vm := FakeG17Vm{}
	file.lock.acquire()
	assert file.reserve_output(mut vm, 0, unsafe { &outputs }) == -22
	assert !file.lock.is_held() && vm.jobs == 3 && file.inflight_jobs == 0
	fence := syncobj.get_fence(binary) or { panic('published prefix') }
	assert notified && syncobj.is_signaled(fence) && syncobj.get_error(fence) == -22,
		'eventfd callback must retire after partial output publication fails'
	syncobj.destroy_owner(111)
	syncobj.free_object_metadata_for_checks(binary)
	syncobj.free_object_metadata_for_checks(timeline)
	unsafe { free(fence) }
}

fn check_transaction() {
	check_partial_publication()
	mut cases := 0
	for render in [-1, 0]! { for allow in [false, true]! {
		for inflight in [u32(0), ~u32(0)]! { for exhausted in [false, true]! {
			old := syncobj.set_context_for_fake_checks(if exhausted { u64(0) } else { u64(1) })
			mut vm := FakeG17Vm{allow: allow}
			mut file := FakeG17File{inflight_jobs: inflight}
			mut previous := syncobj.DmaFence{context: 77, seqno: 8}
			mut object := syncobj.SyncObj{fence: unsafe { &previous }}
			mut objects := unsafe { [64]&syncobj.SyncObj{} }
			objects[0] = unsafe { &object }
			outputs := agxsubmission.SyncArray{count: 1, objects: objects}
			file.lock.acquire()
			code := file.reserve_output(mut vm, render, &outputs)
			assert !file.lock.is_held(), 'submission failure must release the file lock'
			busy := render >= 0 && (!allow || inflight == ~u32(0))
			assert code == if busy { -16 } else if exhausted { -12 } else { 0 }
			if code != 0 {
				assert vm.jobs == 3, 'context exhaustion must unwind the VM pin'
				assert file.inflight_jobs == inflight, 'context exhaustion must unwind the file pin'
				assert object.fence == &previous, 'failure must precede output publication'
			} else {
				assert object.fence != &previous && object.fence.context == 1
				assert vm.jobs == if render >= 0 { u32(4) } else { u32(3) }
				assert file.inflight_jobs == if render >= 0 { inflight + 1 } else { inflight }
				syncobj.signal(object.fence)
				unsafe { free(object.fence) }
			}
			syncobj.set_context_for_fake_checks(old)
			cases++
		} }
	} }
	assert cases == 16
	println('Fake submission transaction: 16 compute/render, VM busy, counter saturation and context exhaustion cases preserve error precedence, pins, lock and outputs.')
}
