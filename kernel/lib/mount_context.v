// SPDX-License-Identifier: GPL-2.0-or-later
module lib

// Values, not allocated views: a shared child mount can be entered through
// different bind aliases. Each holder keeps the bounded route it actually took.
pub struct MountStep {
pub mut:
	identity voidptr
	move_epoch u64
}

pub struct MountContext {
pub mut:
	steps [64]MountStep
	depth int
}

pub fn mount_context_top(context &MountContext) voidptr {
	if context == unsafe { nil } || context.depth <= 0 || context.depth > 64 {
		return unsafe { nil }
	}
	return context.steps[context.depth - 1].identity
}

// Copy into an already owned field or synchronous caller stack slot. All
// identities refer to fs's existing permanent Mount objects.
pub fn copy_mount_context(destination &MountContext, source &MountContext) {
	if destination == unsafe { nil } { return }
	if voidptr(destination) == voidptr(source) { return }
	if source == unsafe { nil } {
		unsafe { C.memset(destination, 0, sizeof(MountContext)) }
	} else {
		unsafe { C.memcpy(destination, source, sizeof(MountContext)) }
	}
}
