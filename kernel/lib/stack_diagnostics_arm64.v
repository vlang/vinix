// SPDX-License-Identifier: GPL-2.0-or-later
module lib

fn C.aarch64__uart__putc(value u8)

fn stack_guard_byte(value u8) {
	C.aarch64__uart__putc(value)
}
