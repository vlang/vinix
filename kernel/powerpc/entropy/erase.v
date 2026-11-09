// SPDX-License-Identifier: GPL-2.0-or-later
module entropy

// A volatile field qualifies the pointed-to byte, rather than just the pointer.
struct SecretByte {
mut:
	volatile value u8
}

// OpenBSD's explicit_bzero(3): the stores must survive even when the caller
// never reads the secret again.
pub fn explicit_bzero(buf voidptr, len uint) {
	for i := uint(0); i < len; i++ {
		unsafe { (&SecretByte(uint(buf) + i)).value = 0 }
	}
}
