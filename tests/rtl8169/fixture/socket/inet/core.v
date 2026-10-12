@[has_globals]
module inet

pub const driver_rtl8169 = 4

__global (
	pub attached      bool
	pub accept_attach bool = true
	pub received      int
	pub last_length   u64
	pub carrier_up    bool
	pub active_driver int
	pub dhcp_starts   int
	pub has_lease     bool
	pub link_up_hook  fn () = unsafe { nil }
)

pub fn link_info(address &[6]u8, mtu &u32) bool { return attached }

pub fn attach(address &[6]u8, kind int) bool {
	attached = accept_attach
	active_driver = kind
	carrier_up = false
	return attached
}

pub fn detach() {
	attached = false
	active_driver = 0
	carrier_up = false
	has_lease = false
}

pub fn detach_owned(kind int) {
	if attached && active_driver == kind { detach() }
}

pub fn attach_if_idle(address &[6]u8, kind int) bool {
	if attached { return false }
	return attach(address, kind)
}

pub fn receive_owned(kind int, frame voidptr, length u64) bool {
	return attached && active_driver == kind && receive(frame, length)
}

pub fn set_link(kind int, up bool) {
	if !attached || kind != active_driver || carrier_up == up { return }
	carrier_up = up
	if up {
		dhcp_starts++
		if link_up_hook != unsafe { nil } { link_up_hook() }
	}
}

pub fn configuration(address &u32, netmask &u32, gateway &u32, dns &[3]u32) bool {
	return has_lease
}

pub fn receive(frame voidptr, length u64) bool {
	received++
	last_length = length
	return true
}
