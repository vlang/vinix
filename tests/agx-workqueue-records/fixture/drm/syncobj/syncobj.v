module syncobj

pub struct DmaFence {
pub mut:
	signaled bool
	error int
	calls int
}
pub fn signal(fence &DmaFence) { signal_error(fence, 0) }
pub fn signal_error(fence &DmaFence, error int) {
	mut owned := unsafe { fence }
	assert !owned.signaled
	owned.signaled = true; owned.error = error; owned.calls++
}
