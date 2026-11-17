@[has_globals]
module workqueue

pub struct WorkQueue {
pub mut:
	vm_id u32
	id u32
	priority u32
	caps u32
	usc_base u64
	detached bool
	destroyed bool
	pooled bool
	pending_count u32
	heap_record bool
	disposed bool
}

__global attempts = 0
__global live = 0
__global reject_next = false
__global heap_next = false
__global last_created &WorkQueue = unsafe { nil }

pub fn creation_attempts() int { return attempts }
pub fn active() int { return live }
pub fn fail_next() { reject_next = true }
pub fn heap_next_record(value bool) { heap_next = value }
pub fn last_record() &WorkQueue { return last_created }

pub fn new_workqueue(id u32, vm_id u32, priority u32, caps u32) ?&WorkQueue {
	attempts++
	if reject_next { reject_next = false; return none }
	live++
	queue := &WorkQueue{ id: id, vm_id: vm_id, priority: priority, caps: caps, pooled: true, heap_record: heap_next }
	heap_next = false
	last_created = queue
	return queue
}

pub fn (mut queue WorkQueue) destroy() {
	assert !queue.destroyed
	queue.destroyed = true
	if queue.pooled { live-- }
}

// Older fixtures observe stack/pool objects after removal. New lifetime cases
// use actual heap records and the extracted production metadata disposer.
pub fn free_workqueue(queue &WorkQueue) {
	mut owned := unsafe { queue }
	assert owned.destroyed && !owned.disposed
	owned.disposed = true
	if owned.heap_record { free_workqueue_real(queue) }
}
