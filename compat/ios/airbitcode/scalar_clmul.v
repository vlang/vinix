// SPDX-License-Identifier: GPL-2.0-or-later
module airbitcode

fn scalar_integer_clmul(bits u32, a u64, b u64) !u64 {
	if bits < 1 || bits > 64 { return error('AIR intrinsic: carry-less multiply width') }
	mask := constant_mask(bits)
	mut term := a & mask; mut remaining := b & mask; mut result := u64(0)
	// Each multiplier bit selects one shifted polynomial term. XOR drops
	// carries; masking each term keeps exactly the low N product bits.
	for remaining != 0 {
		if remaining & 1 != 0 { result ^= term }
		remaining >>= 1
		if remaining != 0 { term = (term << 1) & mask }
	}
	return result
}
