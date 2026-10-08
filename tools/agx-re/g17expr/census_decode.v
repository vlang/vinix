module g17expr

const census_unsigned_widths = {
	u32(0x39000000): 1
	0x79000000:      2
	0xb9000000:      4
	0xf9000000:      8
	0x3d000000:      1
	0x7d000000:      2
	0xbd000000:      4
	0xfd000000:      8
	0x3d800000:      16
}

const census_imm9_widths = {
	u32(0x38000000): 1
	0x78000000:      2
	0xb8000000:      4
	0xf8000000:      8
	0x3c000000:      1
	0x7c000000:      2
	0xbc000000:      4
	0xfc000000:      8
	0x3c800000:      16
}

const census_pair_widths = {
	u32(0x28000000): 4
	0xa8000000:      8
	0x2c000000:      4
	0x6c000000:      8
	0xac000000:      16
}

const census_register_widths = {
	u32(0x38200800): 1
	0x78200800:      2
	0xb8200800:      4
	0xf8200800:      8
	0x3c200800:      1
	0x7c200800:      2
	0xbc200800:      4
	0xfc200800:      8
	0x3ca00800:      16
}

// These are deliberately conservative writers. Forgetting an interior-pointer
// derivation can hide a store; retaining one only adds a reviewable hit.
struct CensusStore {
	base      int
	immediate int
	width     int
	form      string
}

fn census_store(word u32) ?CensusStore {
	if width := census_unsigned_widths[word & 0xffc00000] {
		return CensusStore{int((word >> 5) & 31), int((word >> 10) & 4095) * width, width, 'offset'}
	}

	if width := census_imm9_widths[word & 0xffe00000] {
		amount := int(((word >> 12) & 511) ^ 256) - 256
		forms := ['offset', 'post', 'offset', 'pre']!
		return CensusStore{int((word >> 5) & 31), amount, width, forms[(word >> 10) & 3]}
	}
	op := word & 0xffc00000
	base := op & ~u32(0x01800000)

	if width := census_pair_widths[base] {
		forms := ['offset', 'post', 'offset', 'pre']!
		amount := int(((word >> 15) & 127) ^ 64) - 64
		return CensusStore{int((word >> 5) & 31), amount * width, width * 2, forms[(word >> 23) & 3]}
	}
	size := 1 << (word >> 30)
	if word & 0x3ffffc00 in [u32(0x089ffc00), 0x089f7c00]
		|| word & 0x3fe07c00 == 0x08007c00
		|| word & 0x3fa07c00 == 0x08a07c00
		|| word & 0x3f200c00 == 0x38200000 {
		return CensusStore{int((word >> 5) & 31), 0, size, 'offset'}
	}
	if word & 0xbfe00000 == 0x88200000 {
		return CensusStore{int((word >> 5) & 31), 0, if word & 0x40000000 != 0 { 16 } else { 8 }, 'offset'}
	}
	return none
}

fn census_register_store(word u32) ?[]int {
	width := census_register_widths[word & 0xffe00c00] or { return none }
	shift := if word & 0x1000 != 0 {
		match width {
			1 { 0 }
			2 { 1 }
			4 { 2 }
			8 { 3 }
			else { 4 }
		}
	} else {
		0
	}
	return [int((word >> 5) & 31), int((word >> 16) & 31), shift, width]
}

fn census_written_registers(word u32) []int {
	destination := int(word & 31)
	second := int((word >> 10) & 31)
	if word & 0x1c000000 == 0x10000000 {
		if (word & 0x1f000000 == 0x11000000 && word & 0x20000000 != 0 && destination == 31)
			|| (word & 0x1f800000 == 0x12000000 && word & 0x60000000 == 0x60000000 && destination == 31) {
			return []int{}
		}
		return if destination == 31 { []int{} } else { [destination] }
	}
	if word & 0x0e000000 == 0x0a000000 {
		if word & 0x3fe00000 == 0x3a400000
			|| (word & 0x1f000000 == 0x0a000000 && word & 0x60000000 == 0x60000000 && destination == 31)
			|| (word & 0x1f000000 == 0x0b000000 && word & 0x20000000 != 0 && destination == 31) {
			return []int{}
		}
		return if destination == 31 { []int{} } else { [destination] }
	}
	if word & 0x0a000000 == 0x08000000 {
		vector := word & 0x04000000 != 0
		if word & 0x3b000000 == 0x18000000 {
			return if vector || word & 0xc0000000 == 0xc0000000 { []int{} } else { [destination] }
		}
		if word & 0x3a000000 == 0x28000000 {
			return if word & 0x00400000 == 0 || vector {
				[]int{}
			} else {
				[destination, second]
			}
		}
		if word & 0x3f000000 == 0x08000000 {
			status := int((word >> 16) & 31)
			if word & 0x3fa07c00 == 0x08a07c00 || word & 0xbfa07c00 == 0x08207c00 {
				return [status]
			}
			if word & 0x00400000 != 0 {
				return if word & 0x00200000 == 0 {
					[destination]
				} else {
					[destination, second]
				}
			}
			if word & 0x3fe07c00 == 0x08007c00 || word & 0xbfe00000 == 0x88200000 {
				return [status]
			}
			return []int{}
		}
		if word & 0x3b000000 in [u32(0x38000000), 0x39000000] {
			if vector { return []int{} }
			if word & 0x3f200c00 == 0x38200000 {
				return if destination == 31 { []int{} } else { [destination] }
			}
			opc := (word >> 22) & 3
			if opc == 0 || (opc == 2 && word >> 30 == 3) { return []int{} }
			return [destination]
		}
		return []int{}
	}
	if word & 0x1c000000 == 0x14000000 {
		return if word & 0xfff00000 == 0xd5300000 { [destination] } else { []int{} }
	}
	if word & 0x5f20fc00 == 0x1e200000 {
		return if (word >> 16) & 7 in [u32(0), 1, 4, 5, 6] { [destination] } else { []int{} }
	}
	if word & 0xbfe0fc00 in [u32(0x0e003c00), 0x0e002c00] { return [destination] }
	return []int{}
}

fn census_is_call(word u32) bool {
	return word & 0xfc000000 == 0x94000000 || word & 0xfffffc1f == 0xd63f0000
		|| word & 0xfffff81f == 0xd63f081f || word & 0xfffff800 == 0xd73f0800
}

fn census_writeback(word u32) ?[]int {
	if word & 0x3b200000 == 0x38000000 && (word >> 10) & 3 in [u32(1), 3] {
		return [int((word >> 5) & 31), int(((word >> 12) & 511) ^ 256) - 256]
	}
	if word & 0x3a000000 == 0x28000000 && (word >> 23) & 3 in [u32(1), 3] {
		width := if word & 0x04000000 != 0 {
			4 << ((word >> 30) & 3)
		} else {
			4 << ((word >> 31) & 1)
		}
		return [int((word >> 5) & 31), (int(((word >> 15) & 127) ^ 64) - 64) * width]
	}
	return none
}
