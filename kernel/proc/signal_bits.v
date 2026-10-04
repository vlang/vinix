// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
module proc

import katomic

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

// Take charge of `t`'s exit. Exactly one caller -- the thread leaving on its
// own, or a sibling stopping it -- is told yes.
pub fn claim_thread_exit(t &Thread) bool {
	mut thr := unsafe { t }
	return katomic.cas(mut &thr.exit_claimed, u32(0), u32(1))
}

// ppoll(2), pselect6(2) and epoll_pwait(2) wait under the mask their caller
// hands them, less SIGKILL and SIGSTOP, which cannot be blocked even then. The
// mask from before stays saved for the syscall's end to put back -- after a
// signal that ended the wait has been taken under the wait's mask, with the
// saved one in the handler's frame for sigreturn to restore, as sigsuspend(2)
// does and as Linux does for all four. Put back as the wait returned, the mask
// blocked that signal again: it stayed pending, its handler never ran, and the
// wait's EINTR came for nothing.
pub fn begin_wait_mask(mut t Thread, user_mask u64) {
	t.saved_mask = t.masked_signals
	t.saved_mask_valid = true
	t.masked_signals = sigset_from_user(user_mask & ~((u64(1) << 8) | (u64(1) << 18)))
}
