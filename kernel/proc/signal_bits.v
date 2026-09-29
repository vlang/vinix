// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
module proc

// Masks and pending sets keep signal n in bit n-1, the layout of Linux's
// sigsets, on both architectures, so what userspace hands over is taken as
// it is.
pub fn sigset_from_user(set u64) u64 {
	return set
}

pub fn sigset_to_user(mask u64) u64 {
	return mask
}

// The bit of a pending or masked set signal `signum` takes. 64 is the last
// signal there is.
pub fn pending_bit(signum int) u8 {
	return u8(signum - 1)
}

pub const max_pending_signal = 64
