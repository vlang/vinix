// SPDX-License-Identifier: GPL-2.0-or-later
module airbitcode

import math.bits

fn test_scalar_integer_intrinsic_widths_values_and_names() {
	mut comparisons := 0
	for width in u32(1) .. 65 {
		mask := constant_mask(width)
		for op in ['ctpop', 'bitreverse', 'bswap'] {
			name := 'llvm.${op}.i${width}'; defer { unsafe { name.free() } }
			if op == 'bswap' && width % 16 != 0 {
				if _ := scalar_intrinsic_name(name) { assert false, 'unsupported byte swap width' }; continue
			}
			id := scalar_intrinsic_name(name)!
			assert scalar_intrinsic_arity(id) == 1
			for sample in 0 .. if width <= 16 { int(u64(1) << width) } else { 4096 } {
				value := if width <= 16 { u64(sample) } else { (u64(sample) * u64(0x9e3779b97f4a7c15)) ^ (u64(sample) << 47) }
				x := value & mask
				expected := if op == 'ctpop' { u64(bits.ones_count_64(x)) } else if op == 'bitreverse' { bits.reverse_64(x) >> (64 - width) } else { bits.reverse_bytes_64(x) >> (64 - width) }
				actual := scalar_intrinsic_value(id, width, value, 0)!
				assert actual == expected
				if op != 'ctpop' { assert scalar_intrinsic_value(id, width, actual, 0)! == x }
				comparisons++
			}
		}
	}
	for name in ['llvm.ctpop.i0', 'llvm.ctpop.i01', 'llvm.ctpop.i+1', 'llvm.ctpop.i65', 'llvm.ctpop.i128', 'llvm.ctpop.i1x', 'llvm.ctpop.i1.i32', 'llvm.ctpop.v2i32', 'llvm.bitreverse.f32', 'llvm.bitreverse.i', 'llvm.bswap.i8', 'llvm.bswap.i24', 'air.ctpop.i32'] {
		if _ := scalar_intrinsic_name(name) { assert false, 'unsupported integer intrinsic spelling' }
	}
	for width in [u32(0), 65, 128]! {
		if _ := scalar_intrinsic_value(.ctpop, width, 0, 0) { assert false, 'unsupported integer width' }
	}
	if _ := scalar_integer_intrinsic_value(.fabs, 32, 0) { assert false, 'wrong integer family' }
	if _ := scalar_integer_intrinsic_value(.bswap, 8, 0) { assert false, 'odd byte count' }
	assert scalar_intrinsic_value(.bswap, 48, 0x123456789abc, 0)! == 0xbc9a78563412
	assert scalar_intrinsic_value(.bitreverse, 64, u64(1) << 63, 0)! == 1
	assert scalar_intrinsic_value(.ctpop, 64, ~u64(0), 0)! == 64
	println('AIR-SCALAR-INTEGER-INTRINSICS: ${comparisons} exact comparisons with standard-library bit operations, reversal involutions, all i1..i64 widths, byte swap i16/i32/i48/i64 and strict name/width/arity guards PASS')
}
