// SPDX-License-Identifier: GPL-2.0-or-later
module resource

import errno

pub fn block_health(mut device Resource) ?BlockHealth {
	if mut device is BlockHealthResource {
		mut call := unsafe { &BlockHealthCall(C.vinix_stack_alloc(sizeof(BlockHealthCall))) }
		unsafe { call.device = BlockHealthResource(device) }
		return call.device.block_health()
	}
	errno.set(errno.enotty)
	return none
}
