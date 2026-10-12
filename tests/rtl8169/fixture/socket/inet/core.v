@[has_globals]
module inet

pub const driver_rtl8169 = 4

__global (
	pub attached      bool
	pub accept_attach bool = true
	pub received      int
	pub last_length   u64
)

pub fn link_info(address &[6]u8, mtu &u32) bool { return attached }

pub fn attach(address &[6]u8, kind int) bool {
	attached = accept_attach
	return attached
}

pub fn detach() { attached = false }

pub fn receive(frame voidptr, length u64) {
	received++
	last_length = length
}
