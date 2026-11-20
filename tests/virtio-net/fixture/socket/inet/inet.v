@[has_globals]
module inet

pub const driver_virtio = 1
pub const driver_none = 0

__global (
	attached        bool
	attach_allowed  = true
	packets         int
	echo_on_receive bool
)

fn C.vinix_virtio_net_send(frame voidptr, length u64) int

pub fn reset() {
	attached = false
	attach_allowed = true
	packets = 0
	echo_on_receive = false
}

pub fn deny_attach() {
	attach_allowed = false
}

pub fn echo() {
	echo_on_receive = true
}

pub fn received() int {
	return packets
}

pub fn attach_if_idle(mac &[6]u8, driver int) bool {
	if !attach_allowed || attached { return false }
	attached = true
	// Exercise the synchronous DHCP send performed inside the real attach.
	frame := [64]u8{}
	assert C.vinix_virtio_net_send(unsafe { &frame[0] }, 64) == 0
	_ = mac
	_ = driver
	return true
}

pub fn receive_owned(driver int, frame voidptr, length u64) bool {
	assert driver == driver_virtio && attached
	assert length >= 14
	packets++
	if echo_on_receive { assert C.vinix_virtio_net_send(frame, length) == 0
	 }
	return true
}
