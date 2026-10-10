// SPDX-License-Identifier: GPL-2.0-or-later
module resource

import errno

// ARM has no native health backend yet. V cannot cast an optional interface
// with no concrete Resource implementations in this architecture's build.
pub fn block_health(mut device Resource) ?BlockHealth {
	errno.set(errno.enotty)
	return none
}
