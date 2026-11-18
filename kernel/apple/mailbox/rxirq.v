// SPDX-License-Identifier: GPL-2.0-or-later
module mailbox

fn irq_cell(data voidptr, offset u32) u32 {
	return unsafe {
		p := &u8(u64(data) + offset)
		(u32(p[0]) << 24) | (u32(p[1]) << 16) | (u32(p[2]) << 8) | u32(p[3])
	}
}

// Decode the standard three-cell AICv1 binding and the mailbox's parallel
// interrupt-names property. Both buffers are borrowed for this call only.
pub fn decode_aic_receive_irq(names voidptr, names_size u32, specifiers voidptr, specifiers_size u32) ?u32 {
	if names == unsafe { nil } || specifiers == unsafe { nil } || names_size == 0
		|| specifiers_size == 0 || specifiers_size % 12 != 0 {
		return none
	}
	mut start := u32(0)
	mut index := u32(0)
	mut irq := u32(0)
	for end := u32(0); end < names_size; end++ {
		if unsafe { *&u8(u64(names) + end) } != 0 { continue }
		if end == start || index >= specifiers_size / 12 { return none }
		name := unsafe { tos(&char(u64(names) + start), int(end - start)) }
		if name == 'recv-not-empty' {
			offset := index * 12
			// AIC hardware IRQ (0), followed by its number and level-high (4).
			if irq != 0 || irq_cell(specifiers, offset) != 0
				|| irq_cell(specifiers, offset + 8) != 4 {
				return none
			}
			irq = irq_cell(specifiers, offset + 4)
			if irq == 0 { return none }
		}
		index++
		start = end + 1
	}
	if start != names_size || index != specifiers_size / 12 || irq == 0 {
		return none
	}
	return irq
}
