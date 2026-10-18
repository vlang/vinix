// SPDX-License-Identifier: GPL-2.0-or-later
module g13failure

import g17decode as arm
import traceanalysis as j

pub const driver_uuid = 'AE55928C-9E24-3571-B472-8ECEEB2E5EA1'
pub const event_symbol = '__ZN11AGXFirmware22drainFirmwareEventRingEv'
pub const halt_symbol = '__ZN14AGXArmFirmware32isFirmwareStoppedForHostRecoveryEv'

// These are instruction checks against the active kernel cache read from the
// M1 Air, not assumptions about a similarly named G17 driver or a restore KC.
// Pin the loads, unsigned comparisons, and rejecting branch destinations.
pub fn check_event_code(code []u8) ! {
	arm.require_instruction_words_at(code, 'M1 G13 event ring bounds', {
		0x048: u32(0xf943d809) // ldr x9, [x0, #0x7b0]: state
		0x04c: u32(0xb940012b) // ldr w11, [x9]: read pointer
		0x054: u32(0xb9402129) // ldr w9, [x9, #0x20]: write pointer
		0x05c: u32(0xf943e80a) // ldr x10, [x0, #0x7d0]: capacity
		0x060: u32(0xeb0b015f) // cmp x10, x11
		0x064: u32(0x540089c9) // b.ls +0x119c: reject read >= capacity
		0x068: u32(0xeb09015f) // cmp x10, x9
		0x06c: u32(0x54008a69) // b.ls +0x11b8: reject write >= capacity
		0x318: u32(0x7100201f) // cmp w0, #8: validator dispatch
		0x31c: u32(0x540004a0) // b.eq +0x3b0
		0x3b0: u32(0xb94053e8) // ldr w8, [sp, #0x50]: event tag
		0x3b4: u32(0x7100211f) // cmp w8, #8
		0x3b8: u32(0x54006661) // b.ne +0x1084: reject mismatched tag
		0x3cc: u32(0x52800048) // mov w8, #2: channel-error callback kind
	})!
}

pub fn check_halt_code(code []u8) ! {
	arm.require_instruction_words_at(code, 'M1 G13 host recovery halt', {
		0x04: u32(0xf9448008) // ldr x8, [x0, #0x900]: runtime data
		0x08: u32(0x52894409) // mov w9, #0x4a20
		0x0c: u32(0xb8696908) // ldr w8, [x8, x9]
		0x10: u32(0x7100011f) // cmp w8, #0
		0x14: u32(0x1a9f07e0) // cset w0, ne
		0x18: u32(0xd65f03c0) // ret
	})!
}

pub fn recover(data []u8) !j.Value {
	if arm.macho_uuid(data)! != j.Value(driver_uuid) {
		return error('unsupported M1 AGXG13G driver UUID')
	}
	event_address, event_code := arm.symbol_code(data, event_symbol)!
	check_event_code(event_code)!
	halt_address, halt_code := arm.symbol_code(data, halt_symbol)!
	check_halt_code(halt_code)!
	return j.Value(map[string]j.Value{
		'event_symbol':       j.Value(event_symbol)
		'event_address':      j.Value(event_address)
		'pointer_rule':       j.Value('read < capacity && write < capacity, including empty rings')
		'channel_error_tag':  j.Value(8)
		'halt_symbol':        j.Value(halt_symbol)
		'halt_address':       j.Value(halt_address)
		'native_halt_offset': j.Value(0x4a20)
		'vinix_halt_offset':  j.Value(0x20)
		'abi_note':           j.Value('Native macOS 26.3.1 runtime offset is not a 13.5 wire offset. The 12.3/13.5 FWStatus offset is checked separately against m1n1.')
	})
}
