// SPDX-License-Identifier: GPL-2.0-or-later
module resource

import errno

pub const block_discard_ioctl = u64(0x1277)
pub const block_discard = u64(32)

// The whole interval is checked before issuing any destructive command.
pub fn discard_range_valid(size u64, sector u64, offset u64, bytes u64) bool {
	return sector != 0 && bytes != 0 && offset <= size && bytes <= size - offset
		&& offset % sector == 0 && bytes % sector == 0
}

pub interface DiscardResource {
mut:
	discard(u64, u64) ?
}

struct DiscardCall {
mut:
	device DiscardResource
}

pub fn discard_resource(mut device Resource, offset u64, bytes u64) ? {
	if mut device is DiscardResource {
		mut call := unsafe { &DiscardCall(C.vinix_stack_alloc(sizeof(DiscardCall))) }
		unsafe { call.device = DiscardResource(device) }
		call.device.discard(offset, bytes)?
		return
	}
	errno.set(errno.eopnotsupp)
	return none
}
