module syncobj

pub struct DmaFence {
pub mut:
	signals int
	error   int
}

pub fn signal(fence &DmaFence) {
	mut owned := unsafe { fence }
	owned.signals++
}

pub fn signal_error(fence &DmaFence, error int) {
	mut owned := unsafe { fence }
	owned.error = error
	owned.signals++
}
