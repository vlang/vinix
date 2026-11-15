module workqueue

pub struct WorkQueue {
pub mut:
	vm_id u32
	destroyed bool
}

pub fn (mut queue WorkQueue) destroy() {
	assert !queue.destroyed
	queue.destroyed = true
}
