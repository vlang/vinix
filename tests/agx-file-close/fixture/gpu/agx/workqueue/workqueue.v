@[has_globals]
module workqueue

pub struct WorkQueue {
pub mut:
	vm_id u32
	id u32
	priority u32
	caps u32
	detached bool
	destroyed bool
	pooled bool
}

__global attempts = 0
__global live = 0
__global reject_next = false

pub fn creation_attempts() int { return attempts }
pub fn active() int { return live }
pub fn fail_next() { reject_next = true }

pub fn new_workqueue(id u32, vm_id u32, priority u32, caps u32) ?&WorkQueue {
	attempts++
	if reject_next { reject_next = false; return none }
	live++
	return &WorkQueue{ id: id, vm_id: vm_id, priority: priority, caps: caps, pooled: true }
}

pub fn (mut queue WorkQueue) destroy() {
	assert !queue.destroyed
	queue.destroyed = true
	if queue.pooled { live-- }
}
