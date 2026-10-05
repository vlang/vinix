// SPDX-License-Identifier: GPL-2.0-or-later
module lib

// Fatal/test markers bypass console locks and remain visible in PROD builds.
@[export: 'vinix_stack_guard_message']
fn stack_guard_message(message charptr) {
	unsafe {
		bytes := &u8(message)
		mut i := usize(0)
		for bytes[i] != 0 {
			stack_guard_byte(bytes[i])
			i++
		}
	}
}

fn stack_guard_hex(value u64) {
	for shift := 60; shift >= 0; shift -= 4 {
		digit := u8(value >> u32(shift) & 15)
		stack_guard_byte(if digit < 10 { u8(`0`) + digit } else { u8(`a`) + digit - 10 })
	}
}

// Emit scalar fault evidence without a console lock, formatting buffer or heap.
@[export: 'vinix_stack_guard_diagnostic']
fn stack_guard_diagnostic(sp u64, pc u64, address u64) {
	stack_guard_message(charptr(c'STACK-GUARD state sp=0x'))
	stack_guard_hex(sp)
	stack_guard_message(charptr(c' pc=0x'))
	stack_guard_hex(pc)
	stack_guard_message(charptr(c' address=0x'))
	stack_guard_hex(address)
	stack_guard_byte(u8(`\n`))
}
