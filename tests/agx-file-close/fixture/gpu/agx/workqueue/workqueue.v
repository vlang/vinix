module workqueue

pub struct WorkQueue {
pub mut:
	destroyed bool
}

pub fn (mut queue WorkQueue) destroy() {
	assert !queue.destroyed
	queue.destroyed = true
}
