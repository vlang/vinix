// SPDX-License-Identifier: GPL-2.0-or-later
module probebudget

// An explicit cgroup limit, never a substitute for host free/physical memory.
// Page alignment makes readback identical on Linux and the 4 KiB Vinix guest.
pub fn parse(text string) !u64 {
	if text.len == 0 { return error('memory budget must be decimal bytes') }
	mut bytes := u64(0)
	for digit in text {
		if digit < `0` || digit > `9` {
			return error('memory budget must be positive decimal bytes within int64')
		}
		decimal := u64(digit - `0`)
		// Split int64's decimal quotient/remainder explicitly: the pinned V
		// compiler narrows division of mixed-width expressions to u32.
		if bytes > u64(922337203685477580)
			|| (bytes == u64(922337203685477580) && decimal > 7) {
			return error('memory budget must be positive decimal bytes within int64')
		}
		bytes = bytes * 10 + decimal
	}
	if bytes == 0 || bytes % 4096 != 0 {
		return error('memory budget must be positive and aligned to 4096 bytes')
	}
	return bytes
}
