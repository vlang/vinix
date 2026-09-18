// SPDX-License-Identifier: GPL-2.0-or-later
module securemem

#include <explicit_bzero.h>

fn C.vinix_explicit_bzero(buf voidptr, count usize)

// Erase kernel-owned sensitive storage without dead-store elimination. The
// caller supplies a valid writable span; this is not a usercopy operation.
@[inline]
pub fn zero(buf voidptr, count usize) {
	unsafe { C.vinix_explicit_bzero(buf, count) }
}
