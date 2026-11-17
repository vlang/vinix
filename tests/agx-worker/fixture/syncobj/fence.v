module syncobj

pub struct DmaFence {
pub mut:
	signaled bool
	error int
	waits int
}
pub fn is_signaled(fence &DmaFence) bool { return fence == unsafe { nil } || fence.signaled }
pub fn get_error(fence &DmaFence) int { return if fence == unsafe { nil } { 0 } else { fence.error } }
pub fn wait(fence &DmaFence, duration u64) bool {
	assert duration == 1_000_000
	mut owned := unsafe { fence }; owned.waits++
	assert owned.waits < 10000, 'fence wait failed to make progress'
	return owned.signaled
}
