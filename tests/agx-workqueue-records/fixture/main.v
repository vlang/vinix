import fake
import drm.syncobj
import gpu.agx.workqueue

#include <sanitizer/asan_interface.h>
fn C.__asan_address_is_poisoned(voidptr) int

fn main() {
	for count in [0, 1, 2, 63, 127]! {
		for completed in [false, true]! {
			mut queue := workqueue.new_workqueue(1, 1, 0, 1) or { panic('queue') }
			mut items := [127]workqueue.WorkItem{}
			mut fences := [127]syncobj.DmaFence{}
			for i in 0 .. count {
				items[i].fence = unsafe { &fences[i] }
				assert (queue.submit(unsafe { &items[i] }) or { panic('slot') }) == u32(i)
				if completed { queue.complete(u32(i), 0) }
			}
			queue.destroy()
			assert !queue.lock.is_held() && queue.pending() == 0
			for i in 0 .. count {
				assert fences[i].calls == 1 && fences[i].error == if completed { 0 } else { -3 }
				assert queue.slots[i] == unsafe { nil }
			}
			workqueue.free_workqueue(queue)
			assert C.__asan_address_is_poisoned(queue) != 0, 'logical disposer must free the actual record'
			for i in 0 .. count { assert fences[i].signaled && items[i].submitted }
		}
	}
	fake.check_fake_owners()
	println('AGX logical queues: production cancellation, fence errors, borrowed slots and unlock-before-free passed')
}
