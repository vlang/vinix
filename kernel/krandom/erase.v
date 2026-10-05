// SPDX-License-Identifier: GPL-2.0-or-later
module krandom

// A volatile field qualifies the pointed-to byte, rather than just the pointer.
struct SecretByte {
mut:
	volatile value u8
}

// OpenBSD's explicit_bzero(3): the stores must survive even when the caller
// never reads the secret again. Keep the C ABI for the networking bridge.
@[export: 'vinix_explicit_bzero']
pub fn explicit_bzero(buf voidptr, len usize) {
	for i := usize(0); i < len; i++ {
		unsafe { (&SecretByte(usize(buf) + i)).value = 0 }
	}
}
