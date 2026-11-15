module syncobj

pub fn check_queue_context_allocator() {
	mut contexts := QueueFenceContexts{ next: ~u64(0) - 1 }
	assert (contexts.allocate() or { panic('penultimate context') }) == ~u64(0) - 1
	assert (contexts.allocate() or { panic('final context') }) == ~u64(0)
	assert contexts.allocate() == none && contexts.allocate() == none
	a := new_queue_context() or { panic('context A') }
	b := new_queue_context() or { panic('context B') }
	assert a != 0 && b != 0 && a != b
	fence := new_queue_fence(7, 8, a)
	assert queue_dependency_ready(fence, a) && !is_signaled(fence)
	assert !queue_dependency_ready(fence, b) && !queue_dependency_ready(fence, 0)
	// Public fields and an identical generic fence are not queue provenance.
	generic := new_fence(7, 8)
	assert !queue_dependency_ready(generic, a)
	signal_error(fence, -110)
	assert queue_dependency_ready(fence, b) && get_error(fence) == -110
	assert queue_dependency_ready(unsafe { nil }, 0)
	println('AGX queue contexts: unique scalar identities, exhaustion without wrap/reuse, private provenance and external signal/error readiness passed')
}
