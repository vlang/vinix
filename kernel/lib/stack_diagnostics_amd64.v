// SPDX-License-Identifier: GPL-2.0-or-later
module lib

fn C.serial__panic_out(value u8)

fn stack_guard_byte(value u8) {
	C.serial__panic_out(value)
}
