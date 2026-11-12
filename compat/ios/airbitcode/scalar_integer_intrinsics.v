// SPDX-License-Identifier: GPL-2.0-or-later
module airbitcode

fn scalar_integer_intrinsic(id ScalarIntrinsic) bool {
	return id in [.ctpop, .bitreverse, .bswap]!
}
fn scalar_integer_intrinsic_name(name string) !ScalarIntrinsic {
	id := if name.starts_with('llvm.ctpop.i') { ScalarIntrinsic.ctpop }
		else if name.starts_with('llvm.bitreverse.i') { ScalarIntrinsic.bitreverse }
		else if name.starts_with('llvm.bswap.i') { ScalarIntrinsic.bswap }
		else { return error('AIR intrinsic: unsupported callee') }
	scalar_integer_intrinsic_width(name, id)!
	return id
}
// Inspect bytes directly: no substring allocation and no permissive numeric
// parser that might admit signs, leading zeroes, suffixes or other overloads.
fn scalar_integer_intrinsic_width(name string, id ScalarIntrinsic) !u32 {
	start := match id { .ctpop { 'llvm.ctpop.i'.len } .bitreverse { 'llvm.bitreverse.i'.len } .bswap { 'llvm.bswap.i'.len } else { return error('AIR intrinsic: integer family') } }
	if name.len <= start || name.len > start + 2 || name[start] == `0` { return error('AIR intrinsic: integer overload spelling') }
	mut width := u32(0)
	for i in start .. name.len {
		if name[i] < `0` || name[i] > `9` { return error('AIR intrinsic: integer overload digits') }
		width = width * 10 + u32(name[i] - `0`)
	}
	if width < 1 || width > 64 || (id == .bswap && width % 16 != 0) { return error('AIR intrinsic: integer overload width') }
	return width
}
fn scalar_integer_intrinsic_value(id ScalarIntrinsic, bits u32, value u64) !u64 {
	if !scalar_integer_intrinsic(id) || bits < 1 || bits > 64 || (id == .bswap && bits % 16 != 0) { return error('AIR intrinsic: integer operation/width') }
	mut input := value & constant_mask(bits); mut result := u64(0)
	if id == .bswap {
		for _ in 0 .. bits / 8 { result = (result << 8) | (input & 0xff); input >>= 8 }
	} else {
		for _ in 0 .. bits {
			if id == .ctpop { result += input & 1 } else { result = (result << 1) | (input & 1) }
			input >>= 1
		}
	}
	return result
}
