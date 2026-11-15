// SPDX-License-Identifier: GPL-2.0-or-later
module airbitcode

// Independent rational oracle for all finite binary16 encodings. Keep arithmetic
// on the integer significand and denominator, then encode the integral magnitude.
fn half_round_reference(id ScalarIntrinsic, raw u64) u64 {
	sign := raw & 0x8000; a := raw & 0x7fff
	if a > 0x7c00 { return 0x7e00 }
	if a == 0x7c00 || a == 0 { return raw }
	e := int(a >> 10); shift := if e == 0 { 24 } else { 25 - e }
	if shift <= 0 { return raw }
	numerator := if e == 0 { a } else { 1024 + (a & 1023) }; denominator := u64(1) << u32(shift)
	mut integer := numerator / denominator; remainder := numerator % denominator
	if (id == .floor && sign != 0 && remainder != 0) || (id == .ceil && sign == 0 && remainder != 0) || (id == .round && remainder * 2 >= denominator) || (id in [.roundeven, .rint, .nearbyint]! && (remainder * 2 > denominator || (remainder * 2 == denominator && integer % 2 == 1))) { integer++ }
	if integer == 0 { return sign }
	mut exponent := 0; for (u64(1) << u32(exponent + 1)) <= integer { exponent++ }
	fraction := if exponent <= 10 { (integer - (u64(1) << u32(exponent))) << u32(10 - exponent) } else { (integer - (u64(1) << u32(exponent))) >> u32(exponent - 10) }
	return sign | (u64(exponent + 15) << 10) | fraction
}
fn test_vector_rounding_every_half_encoding() {
	mut checks := 0
	for id in [ScalarIntrinsic.floor, .ceil, .trunc, .round, .roundeven, .rint, .nearbyint]! {
		for sample in 0 .. 65536 {
			mut source := ScalarVectorValue{}
			for lane in 0 .. 16 { source.lanes[lane] = IntegerValue{value: u64((sample + lane) % 65536) | ~u64(0xffff)} }
			before := source; result := rounding_intrinsic_vector(id, source, 16, 16)!
			for lane in 0 .. 16 { assert result.lanes[lane] == IntegerValue{value: half_round_reference(id, u64((sample + lane) % 65536))}; checks++ }
			assert source == before && result.undef == 0
		}
	}
	assert checks == 7340032
	println('AIR-VECTOR-ROUND-VALUES: ${checks} independent rational binary16 checks across all encodings, seven operations and 16 lanes, upper-bit masking and snapshots PASS')
}
fn test_vector_rounding_names_states_and_cache() {
	mut seen := [vector_float_intrinsic_slots]bool{}; mut checks := 0
	for bits in [u32(16), 32]! { for id in [ScalarIntrinsic.fabs, .copysign, .floor, .ceil, .trunc, .round, .roundeven, .rint, .nearbyint, .sqrt, .minimum, .maximum, .minimumnum, .maximumnum, .minnum, .maxnum, .fma, .fmuladd, .ldexp, .is_fpclass]! { for count in 1 .. 17 {
		base := 'llvm.${if id == .is_fpclass { 'is.fpclass' } else { id.str() }}.v${count}f${bits}'; name := if id == .ldexp { base + '.v${count}i32' } else { base }; parsed, n, b := vector_float_intrinsic_name(name)!; assert parsed == id && n == count && b == bits
		key := vector_float_intrinsic_key(id, count, bits)!; assert !seen[key]; seen[key] = true
		if id in [.fabs, .copysign]! { assert key == vector_sign_intrinsic_key(id, count, bits)!; continue }
		if id == .sqrt { assert key >= 288; continue }
		if id == .fma { assert key >= 512; continue }
		if id == .fmuladd { assert key >= 544; continue }
		if id == .ldexp { assert key >= 576; continue }
		if id == .is_fpclass { assert key >= 608; continue }
		if id in [.minimum, .maximum, .minimumnum, .maximumnum, .minnum, .maxnum]! { assert key >= 320; continue }
		for target in 0 .. count {
			mut source := ScalarVectorValue{}; source.lanes[target] = IntegerValue{poison: true}; result := rounding_intrinsic_vector(id, source, bits, count)!
			for lane in 0 .. count { assert result.lanes[lane].poison == (lane == target); checks++ }; assert frozen_vector(result, count)!.lanes[target] == IntegerValue{}
			source.undef = u16(1) << u32(target); if _ := rounding_intrinsic_vector(id, source, bits, count) { assert false, 'strict undef' }; checks++
		}
	} } }
 for bits in u32(1) .. 65 { for count in 1 .. 17 {
  id, n, width := vector_float_intrinsic_name('llvm.ctpop.v${count}i${bits}')!; assert id == .ctpop && n == count && width == bits
  key := vector_float_intrinsic_key(id, count, bits)!; assert key >= 640 && key < 1664 && !seen[key]; seen[key] = true
 } }
 for bits in u32(1) .. 65 { for count in 1 .. 17 {
  id, n, width := vector_float_intrinsic_name('llvm.bitreverse.v${count}i${bits}')!; assert id == .bitreverse && n == count && width == bits
  key := vector_float_intrinsic_key(id, count, bits)!; assert key >= 1664 && key < 2688 && !seen[key]; seen[key] = true
 } }
 for bits in [u32(16),32,48,64]! { for count in 1 .. 17 {
  id, n, width := vector_float_intrinsic_name('llvm.bswap.v${count}i${bits}')!; assert id == .bswap && n == count && width == bits
  key := vector_float_intrinsic_key(id, count, bits)!; assert key >= 2688 && key < 2752 && !seen[key]; seen[key] = true
 } }
 for bits in u32(1) .. 65 {for count in 1 .. 17 {
  id,n,width:=vector_float_intrinsic_name('llvm.ctlz.v${count}i${bits}')!;assert id==.ctlz&&n==count&&width==bits
  key:=vector_float_intrinsic_key(id,count,bits)!;assert key>=2752&&key<3776&&!seen[key];seen[key]=true
 }}
 for bits in u32(1) .. 65 {for count in 1 .. 17 {
  id,n,width:=vector_float_intrinsic_name('llvm.cttz.v${count}i${bits}')!;assert id==.cttz&&n==count&&width==bits
  key:=vector_float_intrinsic_key(id,count,bits)!;assert key>=3776&&key<4800&&!seen[key];seen[key]=true
 }}
	for slot in seen { assert slot }
	for name in ['llvm.floor.f32', 'llvm.floor.v0f16', 'llvm.floor.v01f32', 'llvm.floor.v17f16', 'llvm.floor.v99999999999999999999f16', 'llvm.floor.v2f64', 'llvm.floor.v2bf16', 'llvm.floor.v2f016', 'llvm.floor.v2f32.spoof', 'llvm.floor.nxv2f32', 'llvm.roundeven.vf32', 'llvm.nearbyint.v2i32', 'llvm.sin.v2f32'] { if _, _, _ := vector_float_intrinsic_name(name) { assert false, name } }
	for id in [ScalarIntrinsic.fabs, .sqrt, .fma]! { if _ := rounding_intrinsic_vector(id, ScalarVectorValue{}, 32, 1) { assert false, 'family' } }
	for width in [u32(0), 1, 64]! { if _ := rounding_intrinsic_vector(.floor, ScalarVectorValue{}, width, 1) { assert false, 'width' } }
	for count in [0, 17] { if _ := rounding_intrinsic_vector(.floor, ScalarVectorValue{}, 16, count) { assert false, 'count' } }
	for tag in [IntegerValue{aggregate: true}, IntegerValue{vector: true}] { mut source := ScalarVectorValue{}; source.lanes[0] = tag; if _ := rounding_intrinsic_vector(.floor, source, 32, 1) { assert false, 'scalar tag' } }
	assert checks == 22848
	println('AIR-VECTOR-ROUND-STATES: ${checks} lane poison/undef/freeze checks; all 640 floating, 1024 population-count and 1024 bit-reversal and 64 byte-swap and 1024 leading-zero and 1024 trailing-zero overload/cache identities and family/shape/name/tag guards PASS')
}
