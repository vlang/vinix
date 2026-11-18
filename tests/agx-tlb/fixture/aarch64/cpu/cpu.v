@[has_globals]
module cpu

__global watched_descriptor = unsafe { &u64(nil) }
__global barrier_value = u64(0)
__global barriers = 0

pub fn watch_descriptor(descriptor &u64) {
	watched_descriptor = unsafe { descriptor }
	barrier_value = 0
	barriers = 0
}

pub fn descriptor_at_barrier() (u64, int) {
	return barrier_value, barriers
}

pub fn dsb_sy() {
	if watched_descriptor != unsafe { nil } {
		barrier_value = unsafe { *watched_descriptor }
		barriers++
	}
}
