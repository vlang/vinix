// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
//
// Signed signal frames, as OpenBSD has them since 6.4. rt_sigreturn(2)
// loads every register from memory the program controls, which makes it the
// ideal gadget for an exploit: sigreturn-oriented programming forges a frame
// on the stack and calls it. Every frame the kernel builds therefore carries
// a cookie, the process's secret mixed with the frame's own address, which
// rt_sigreturn checks before it believes a word of the frame, and clears once
// it has, so that the frame cannot be replayed. A forged frame kills the
// process with SIGSEGV, as a frame Linux cannot read does.
module proc

import krandom

// A secret for a program about to start: exec picks one, fork keeps it, since
// a child returns through the frames its parent's handlers were given. The
// first programs may start before the generator is seeded; a guessable secret
// is still better than none there.
pub fn new_sigcookie() u64 {
	mut cookie := u64(0)
	krandom.fill(voidptr(&cookie), sizeof(cookie), true)
	return cookie
}

// The cookie the frame at `address` carries.
@[inline]
pub fn sigframe_cookie(process &Process, address u64) u64 {
	return process.sigcookie ^ address
}
