// SPDX-License-Identifier: GPL-2.0-or-later
module fake

import drm.syncobj
import gpu.agx.submission as agxsubmission
import klock

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

fn check_transaction() {
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
