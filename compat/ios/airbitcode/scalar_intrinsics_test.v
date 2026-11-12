// SPDX-License-Identifier: GPL-2.0-or-later
module airbitcode

fn test_scalar_intrinsic_bits_and_rounding() {
	cases := [
		[u64(0), 16, 0xfc01, 0, 0x7c01], [u64(1), 16, 0x7c01, 0x8000, 0xfc01],
		[u64(0), 32, 0xff812345, 0, 0x7f812345], [u64(1), 32, 0x7f812345, 0x80000000, 0xff812345],
		[u64(2), 16, 1, 0, 0], [u64(2), 16, 0x8001, 0, 0xbc00],
		[u64(3), 16, 1, 0, 0x3c00], [u64(3), 16, 0x8001, 0, 0x8000],
		[u64(4), 16, 0xbe00, 0, 0xbc00], [u64(4), 32, 0x80000001, 0, 0x80000000],
		[u64(5), 16, 0x3800, 0, 0x3c00], [u64(5), 16, 0xb800, 0, 0xbc00],
		[u64(6), 16, 0x3800, 0, 0], [u64(6), 16, 0xb800, 0, 0x8000],
		[u64(6), 16, 0x3e00, 0, 0x4000], [u64(6), 16, 0x4100, 0, 0x4000],
		[u64(6), 32, 0x3f000000, 0, 0], [u64(6), 32, 0xbf000001, 0, 0xbf800000],
		[u64(6), 32, 0x3fc00000, 0, 0x40000000], [u64(6), 32, 0x40200000, 0, 0x40000000],
		[u64(5), 32, 0x40200000, 0, 0x40400000], [u64(2), 32, 0x4b000000, 0, 0x4b000000],
		[u64(3), 32, 0x7f800000, 0, 0x7f800000], [u64(4), 16, 0xfc00, 0, 0xfc00],
		[u64(7), 16, 0xbe00, 0, 0xc000], [u64(8), 32, 0x40200000, 0, 0x40000000],
		[u64(2), 16, 0x7c01, 0, 0x7e00], [u64(3), 32, 0xff812345, 0, 0x7fc00000],
	]
	defer { unsafe { for row in cases { row.free() }; cases.free() } }
	for row in cases { assert scalar_intrinsic_value(unsafe { ScalarIntrinsic(row[0]) }, u32(row[1]), row[2], row[3])! == row[4], '${row}' }
	if _ := scalar_intrinsic_value(.fabs, 64, 0, 0) { assert false, 'unsupported precision' }
	for name in ['air.fabs.f32', 'llvm.fabs.f64', 'llvm.fabs.v2f32', 'llvm.sin.f32', 'llvm.fabs.f32.spoof'] { if _ := scalar_intrinsic_name(name) { assert false, 'unsupported name' } }
	println('AIR-SCALAR-INTRINSIC-VALUES: ${cases.len} exact sign/payload/rounding/zero/subnormal/infinity/NaN patterns and unsupported name/width guards PASS')
}

fn test_scalar_intrinsic_square_root() {
	cases := [[u64(16), 0, 0], [u64(16), 0x8000, 0x8000], [u64(16), 0x3c00, 0x3c00],
		[u64(16), 0x4400, 0x4000], [u64(16), 0x4880, 0x4200], [u64(16), 0x4000, 0x3da8],
		[u64(16), 0x4500, 0x4079],
		[u64(16), 1, 0x0c00], [u64(16), 0x0400, 0x2000], [u64(16), 0x7bff, 0x5bff],
		[u64(16), 0xbc00, 0x7e00], [u64(16), 0x8001, 0x7e00], [u64(16), 0x7c00, 0x7c00],
		[u64(16), 0xfc00, 0x7e00], [u64(16), 0xfc01, 0x7e00], [u64(16), 0x7e55, 0x7e00],
		[u64(32), 0, 0], [u64(32), 0x80000000, 0x80000000], [u64(32), 0x3f800000, 0x3f800000],
		[u64(32), 0x40800000, 0x40000000], [u64(32), 0x41100000, 0x40400000], [u64(32), 0x40000000, 0x3fb504f3],
		[u64(32), 0x40a00000, 0x400f1bbd],
		[u64(32), 1, 0x1a3504f3], [u64(32), 0x00800000, 0x20000000], [u64(32), 0x7f7fffff, 0x5f7fffff],
		[u64(32), 0xbf800000, 0x7fc00000], [u64(32), 0x80000001, 0x7fc00000], [u64(32), 0x7f800000, 0x7f800000],
		[u64(32), 0xff800000, 0x7fc00000], [u64(32), 0xff800001, 0x7fc00000], [u64(32), 0x7fc12345, 0x7fc00000]]
	defer { unsafe { for row in cases { row.free() }; cases.free() } }
	for row in cases { assert scalar_intrinsic_value(.sqrt, u32(row[0]), row[1], 0)! == row[2], '${row}' }
	for name in ['llvm.sqrt.f16', 'llvm.sqrt.f32'] { assert scalar_intrinsic_arity(scalar_intrinsic_name(name)!) == 1 }
	for name in ['llvm.sqrt.f64', 'llvm.sqrt.v2f32', 'air.sqrt.f32', 'llvm.sqrt.f32.spoof'] { if _ := scalar_intrinsic_name(name) { assert false, 'unsupported square root name' } }
	// Independent multiplication inequalities verify the integer primitive,
	// including exact squares and their neighbors at the 54-bit bound.
	for sample in 0 .. 65536 {
		candidate := (u64(sample) * 0x1f123bb5) & 0x7ffffff
		for radicand in [u64(sample), candidate * candidate, candidate * candidate + 1, if candidate == 0 { u64(0) } else { candidate * candidate - 1 }, (u64(1) << 54) - 1 - u64(sample)]! {
			root, remainder := scalar_sqrt_root(radicand)
			assert root * root <= radicand && (root + 1) * (root + 1) > radicand
			assert remainder == radicand - root * root
		}
	}
	println('AIR-SCALAR-SQRT: ${cases.len} exact results, unary name/width guards and 327680 integer root/remainder inequalities PASS')
}
fn test_scalar_intrinsic_attribute_encodings_and_budget() {
	blocks := [Block{parent: -1}, Block{id: 9, parent: 0}, Block{id: 10, parent: 0}]
	records := [Record{block: 1, code: 2, values_count: 1}, Record{block: 2, code: 3, values_start: 1, values_count: 9}]
	mut values := [u64(7), 7, 0xffffffff, 0, 18, 0, 105, 1, 86, 0]
	defer { unsafe { blocks.free(); records.free(); values.free() } }
	stream := Stream{blocks: blocks, records: records, values: values}
	assert scalar_intrinsic_attributes(stream, 0, 0)! == 0
	for version in u64(0) .. 3 { values[9] = version << 56; assert scalar_intrinsic_attributes(stream, 1, 64)! > 0 }
	for bad in [u64(1), u64(3) << 56]! { values[9] = bad; if _ := scalar_intrinsic_attributes(stream, 1, 64) { assert false, 'memory effects/version' } }
	values[9] = 0; values[3] = 3
	if _ := scalar_intrinsic_attributes(stream, 1, 64) { assert false, 'string attribute' }
	values[3] = 0; values[4] = 54
	if _ := scalar_intrinsic_attributes(stream, 1, 64) { assert false, 'strictfp' }
	values[4] = 18; values[2] = 0
	if _ := scalar_intrinsic_attributes(stream, 1, 64) { assert false, 'return attribute' }
	values[2] = 1
	if _ := scalar_intrinsic_attributes(stream, 1, 64) { assert false, 'parameter attribute' }
	values[2] = 0xffffffff
	if _ := scalar_intrinsic_attributes(stream, 2, 64) { assert false, 'missing attribute list' }
	if _ := scalar_intrinsic_attributes(stream, 1, 1) { assert false, 'attribute scan budget' }
	println('AIR-SCALAR-INTRINSIC-ATTRIBUTES: canonical function enums and memory(none) versions 0/1/2, memory/strictfp/string/return/parameter/missing/budget guards PASS')
}

fn test_scalar_intrinsic_minimum_maximum() {
	// Both argument orders must agree, including signed zeros and sNaNs.
	for bits in [u32(16), 32]! {
		sign := u64(1) << (bits - 1)
		one := if bits == 16 { u64(0x3c00) } else { u64(0x3f800000) }
		inf := if bits == 16 { u64(0x7c00) } else { u64(0x7f800000) }
		qn := if bits == 16 { u64(0x7e00) } else { u64(0x7fc00000) }
		cases := [[u64(0), sign, sign, 0], [sign, sign, sign, sign], [u64(0), 0, 0, 0],
			[one, one | sign, one | sign, one], [one | sign, 1 | sign, one | sign, 1 | sign],
			[u64(1), one, 1, one], [inf, one, one, inf], [inf | sign, inf, inf | sign, inf],
			[inf + 1, one, qn, qn], [one, (qn + 1) | sign, qn, qn],
			[inf + 1, (inf + 1) | sign, qn, qn]]
		defer { unsafe { for row in cases { row.free() }; cases.free() } }
		for row in cases {
			for swapped in [false, true]! {
				a := row[int(swapped)]; b := row[int(!swapped)]
				assert scalar_intrinsic_value(.minimum, bits, a, b)! == row[2]
				assert scalar_intrinsic_value(.maximum, bits, a, b)! == row[3]
			}
		}
		for op in ['minimum', 'maximum'] {
			name := 'llvm.${op}.f${bits}'; defer { unsafe { name.free() } }
			assert scalar_intrinsic_arity(scalar_intrinsic_name(name)!) == 2
		}
	}
	for name in ['llvm.minnum.f32', 'llvm.maxnum.f16', 'llvm.minimum.f64', 'llvm.maximum.v2f32', 'air.minimum.f32'] {
		if _ := scalar_intrinsic_name(name) { assert false, 'unsupported extremum name' }
	}
	println('AIR-SCALAR-EXTREMA: 88 exact results across both precisions/orders, binary arity and unsupported names PASS')
}
