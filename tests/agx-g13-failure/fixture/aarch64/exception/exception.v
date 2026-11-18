// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module exception

__global dispatch_test_irq fn (voidptr) = unsafe { nil }

pub fn register_irq_dispatch(handler fn (voidptr)) {
	dispatch_test_irq = handler
}

pub fn dispatch() {
	dispatch_test_irq(unsafe { nil })
}
