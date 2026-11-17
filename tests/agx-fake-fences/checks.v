// SPDX-License-Identifier: GPL-2.0-or-later
module fake

import drm.syncobj
import gpu.agx.workqueue
import memory

fn C.__builtin_alloca(uint) voidptr

fn check_order(order [4]int, separate_queues bool) {
	memory.reset()
	mut source := syncobj.SyncObj{}
	mut destination := syncobj.SyncObj{}
	mut queues := unsafe { &workqueue.WorkQueue(C.__builtin_alloca(4 * sizeof(workqueue.WorkQueue))) }
	mut items := [4]workqueue.WorkItem{}
	mut leaves := unsafe { [4]&syncobj.DmaFence{} }
	mut nodes := unsafe { [4]&syncobj.DmaFence{} }
	mut slots := [4]u32{}
	for i in 0 .. 4 {
		// Identical userspace queue IDs, a constant clock and file reuse cannot
		// affect a constructor that takes neither names nor timestamps.
		unsafe { queues[i] = workqueue.WorkQueue{id: 1} }
		fence := new_submission_fence() or { panic('fake fence') }
		leaves[i] = fence
		for j in 0 .. i {
			assert leaves[j].context != fence.context, 'independent fake jobs need distinct contexts'
		}
		items[i].fence = fence
		qi := if separate_queues { i } else { 0 }
		mut queue := unsafe { &queues[qi] }
		slots[i] = queue.submit(unsafe { &items[i] }) or { panic('slot') }
		nodes[i] = syncobj.reserve_chain() or { panic('source chain') }
		assert syncobj.add_chain_point(&source, nodes[i], fence, u64(i + 1))
		assert !syncobj.queue_dependency_ready(fence, fence.context), 'fake fences cannot elide queue dependencies'
	}
	merged := syncobj.unwrap_merge(source.fence) or { panic('merge') }
	assert syncobj.array_count_for_checks(merged) == 4, 'merge must retain every independent fake job'
	head := syncobj.reserve_chain() or { panic('destination chain') }
	assert syncobj.add_chain_point(&destination, head, merged, 9)
	for step, i in order {
		qi := if separate_queues { i } else { 0 }
		mut queue := unsafe { &queues[qi] }
		queue.complete(slots[i], if step == 0 { workqueue.work_err_fault } else { workqueue.work_err_none })
		assert syncobj.is_signaled(head) == (step == 3), 'merged fake jobs must all complete'
		assert syncobj.is_signaled(merged) == (step == 3)
	}
	assert syncobj.get_error(merged) == -int(workqueue.work_err_fault)
	for i in 0 .. 4 {
		mut queue := unsafe { &queues[i] }
		assert queue.is_empty(); queue.destroy()
	}
	// Fixture-only reclamation after all children, callbacks and consumers
	// finish. Production published fence/chain retention remains unchanged.
	assert syncobj.is_signaled(head)
	memory.free(voidptr(head))
	syncobj.dispose_merged_for_checks(merged)
	for i in 0 .. 4 { memory.free(voidptr(nodes[i])); unsafe { free(leaves[i]) } }
	memory.reset()
}

pub fn run_checks() {
	mut cases := 0
	for separate in [false, true]! {
		for a in 0 .. 4 { for b in 0 .. 4 { if b == a { continue }
			for c in 0 .. 4 { if c == a || c == b { continue }
				for d in 0 .. 4 { if d == a || d == b || d == c { continue }
					check_order([a, b, c, d]!, separate); cases++
				}
			}
		} }
	}
	assert cases == 48
	// The last context is usable once; exhaustion stays exhausted and never
	// creates a zero-context fence. Restore before the full DRM regressions.
	old := syncobj.set_context_for_fake_checks(~u64(0))
	last := new_submission_fence() or { panic('last context') }
	assert last.context == ~u64(0) && last.seqno == 1
	for _ in 0 .. 1000 {
		if _ := new_submission_fence() { panic('exhausted contexts must reject fake submission') }
	}
	assert syncobj.set_context_for_fake_checks(old) == 0
	syncobj.signal(last)
	unsafe { free(last) }
	check_transaction()
	println('Fake fences: 48 same/cross-queue completion permutations retain all dependencies; unique contexts, error propagation, no elision and 1000 exhausted allocations pass.')
}
