// SPDX-License-Identifier: GPL-2.0-or-later
module krandom

// Preserve native size_t in C interfaces on the pinned and current compilers.
@[typedef]
pub type C.size_t = u64

// A volatile field qualifies the pointed-to byte, rather than just the pointer.
struct SecretByte {
mut:
	volatile value u8
}

// OpenBSD's explicit_bzero(3): the stores must survive even when the caller
// never reads the secret again. Keep the C ABI for the networking bridge.
@[export: 'vinix_explicit_bzero']
pub fn explicit_bzero(buf voidptr, len C.size_t) {
	for i := u64(0); i < len; i++ {
		unsafe { (&SecretByte(u64(buf) + i)).value = 0 }
	}
}
