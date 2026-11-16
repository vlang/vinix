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
 for id in [ScalarIntrinsic.fshl, .fshr]! {for bits in u32(1) .. 65 {for count in 1 .. 17 {
  actual,n,width:=vector_float_intrinsic_name('llvm.${id}.v${count}i${bits}')!;assert actual==id&&n==count&&width==bits
  key:=vector_float_intrinsic_key(id,count,bits)!;assert key>=4800&&key<6848&&!seen[key];seen[key]=true
 }}}
 for id in [ScalarIntrinsic.smin,.smax,.umin,.umax]! {for bits in u32(1)..65 {for count in 1..17 {
  actual,n,width:=vector_float_intrinsic_name('llvm.${id}.v${count}i${bits}')!;assert actual==id&&n==count&&width==bits
  key:=vector_float_intrinsic_key(id,count,bits)!;assert key>=6848&&key<10944&&!seen[key];seen[key]=true
 }}}
 for bits in u32(1)..65 {for count in 1..17 {
  id,n,width:=vector_float_intrinsic_name('llvm.abs.v${count}i${bits}')!;assert id==.iabs&&n==count&&width==bits
  key:=vector_float_intrinsic_key(id,count,bits)!;assert key>=10944&&key<11968&&!seen[key];seen[key]=true
 }}
 for id in [ScalarIntrinsic.sadd_sat,.uadd_sat,.ssub_sat,.usub_sat]! {for bits in u32(1)..65 {for count in 1..17 {
  prefix:=match id{.sadd_sat{'sadd.sat'} .uadd_sat{'uadd.sat'} .ssub_sat{'ssub.sat'} else{'usub.sat'}}
  parsed,n,width:=vector_float_intrinsic_name('llvm.${prefix}.v${count}i${bits}')!;assert parsed==id&&n==count&&width==bits
  key:=vector_float_intrinsic_key(id,count,bits)!;assert key>=11968&&key<16064&&!seen[key];seen[key]=true
 }}}
 for id in [ScalarIntrinsic.sshl_sat,.ushl_sat]!{for bits in u32(1)..65{for n in 1..17{prefix:=if id==.sshl_sat{'sshl.sat'}else{'ushl.sat'};parsed,count,w:=vector_float_intrinsic_name('llvm.${prefix}.v${n}i${bits}')!;assert parsed==id&&count==n&&w==bits;key:=vector_float_intrinsic_key(id,n,bits)!;assert key>=16064&&key<18112&&!seen[key];seen[key]=true}}}
	for id in [ScalarIntrinsic.fptosi_sat, .fptoui_sat]! { for source in [u32(16), 32]! { for bits in u32(1) .. 65 { for count in 1 .. 17 {
		prefix := if id == .fptosi_sat { 'fptosi' } else { 'fptoui' }
		name := 'llvm.${prefix}.sat.v${count}i${bits}.v${count}f${source}'
		parsed, n, input, output := vector_saturating_cast_name(name)!
		assert parsed == id && n == count && input == source && output == bits
		key := vector_saturating_cast_key(id, count, source, bits)!
		assert key >= 18112 && key < 22208 && !seen[key]; seen[key] = true
		unsafe { name.free() }
	} } } }
	for id in [ScalarIntrinsic.pext, .pdep]! { for bits in u32(1) .. 65 { for count in 1 .. 17 {
		parsed, n, width := vector_float_intrinsic_name('llvm.${id}.v${count}i${bits}')!; assert parsed == id && n == count && width == bits
		key := vector_float_intrinsic_key(id, count, bits)!; assert key >= 22208 && key < 24256 && !seen[key]; seen[key] = true
	} } }
	for bits in u32(1) .. 65 { for count in 1 .. 17 {
		id, n, width := vector_float_intrinsic_name('llvm.clmul.v${count}i${bits}')!; assert id == .clmul && n == count && width == bits
		key := vector_float_intrinsic_key(id, count, bits)!; assert key >= 24256 && key < 25280 && !seen[key]; seen[key] = true
	} }
	for op, name in ['add','mul','and','or','xor','smin','smax','umin','umax'] { for bits in u32(1) .. 65 { for count in 1 .. 17 {
		id, n, width := vector_reduction_name('llvm.vector.reduce.${name}.v${count}i${bits}')!; assert int(id) == op && n == count && width == bits
		key := vector_reduction_key(id, count, bits)!; assert key >= 25280 && key < 34496 && !seen[key]; seen[key] = true
	} } }
	for id in [ScalarIntrinsic.minimum, .maximum]! { for bits in [u32(16), 32]! { for count in 1 .. 17 {
		name := 'llvm.vector.reduce.f' + id.str() + '.v' + count.str() + 'f' + bits.str(); parsed, n, width := floating_vector_reduction_name(name)!; assert parsed == id && n == count && width == bits
		key := floating_vector_reduction_key(id, count, bits)!; assert key >= 34496 && key < 34560 && !seen[key]; seen[key] = true
	} } }
	for id in [FloatingSequentialReduction.sum, .product]! { for bits in [u32(16), 32]! { for count in 1 .. 17 {
		name := 'llvm.vector.reduce.' + (if id == .sum {'fadd'} else {'fmul'}) + '.v' + count.str() + 'f' + bits.str(); parsed, n, width := sequential_vector_reduction_name(name)!; assert parsed == id && n == count && width == bits
		key := sequential_vector_reduction_key(id, count, bits)!; assert key >= 34560 && key < 34624 && !seen[key]; seen[key] = true
	} } }
	for id in [ScalarIntrinsic.minnum, .maxnum]! { for bits in [u32(16), 32]! { for count in 1 .. 17 {
		name := 'llvm.vector.reduce.' + (if id == .minnum {'fmin'} else {'fmax'}) + '.v' + count.str() + 'f' + bits.str(); parsed, n, width := number_vector_reduction_name(name)!; assert parsed == id && n == count && width == bits
		key := number_vector_reduction_key(id, count, bits)!; assert key >= 34624 && key < 34688 && !seen[key]; seen[key] = true
	} } }
	for id in [ScalarIntrinsic.minimumnum, .maximumnum]! { for bits in [u32(16), 32]! { for count in 1 .. 17 {
		name := 'llvm.vector.reduce.f' + id.str() + '.v' + count.str() + 'f' + bits.str(); parsed, n, width := number_vector_reduction_name(name)!; assert parsed == id && n == count && width == bits
		key := number_vector_reduction_key(id, count, bits)!; assert key >= 34688 && key < 34752 && !seen[key]; seen[key] = true
	} } }
	for bits in [u32(16), 32]! { for count in 1 .. 17 { key := vector_float_intrinsic_key(.canonicalize, count, bits)!; assert key >= 34752 && key < 34784 && !seen[key]; seen[key] = true } }
	for id in [ScalarIntrinsic.smulh, .umulh]! { for bits in u32(1) .. 65 { for count in 1 .. 17 { key := vector_float_intrinsic_key(id, count, bits)!; assert key >= 34784 && key < 36832 && !seen[key]; seen[key] = true } } }
	for format in 0 .. 66 { for count in 1 .. 17 { key := vector_reverse_key(count, format)!; assert key >= 36832 && key < 37888 && !seen[key]; seen[key] = true } }
	for id in [ScalarIntrinsic.vector_splice_left, .vector_splice_right]! { for format in 0 .. 66 { for count in 1 .. 17 { key := vector_splice_key(id, count, format)!; assert key >= 37888 && key < 40000 && !seen[key]; seen[key] = true } } }
	for id in [ScalarIntrinsic.vector_interleave2, .vector_interleave3, .vector_interleave4, .vector_interleave5, .vector_interleave6, .vector_interleave7, .vector_interleave8]! { factor := scalar_intrinsic_arity(id); for format in 0 .. 66 { for n in 1 .. 16 / factor + 1 { key := vector_interleave_key(id, n * factor, format)!; assert key >= 40000 && key < 41716 && !seen[key]; seen[key] = true } } }
	for width in u32(8) .. 65 { for count in 1 .. 17 { key := vector_step_key(count, width)!; assert key >= 41716 && key < 42628 && !seen[key]; seen[key] = true } }
	for width in u32(1) .. 65 { for count in 1 .. 17 { key := vector_active_mask_key(count, width)!; assert key >= 42628 && key < 43652 && !seen[key]; seen[key] = true } }
	for format in 0 .. 66 { for source in 1 .. 17 { for count in 1 .. source + 1 { key := vector_subvector_key(count, source, format)!; assert key >= 43652 && key < 52628 && !seen[key]; seen[key] = true } } }
	for format in 0 .. 66 { for count in 1 .. 17 { for source in 1 .. count + 1 { key := vector_subinsert_key(count, source, format)!; assert key >= 52628 && key < 61604 && !seen[key]; seen[key] = true } } }
	for id in [ScalarIntrinsic.fabs, .floor, .ceil, .trunc, .sqrt, .round, .rint]! { for count in 1 .. 17 {
		key := air_vector_unary_key(id, count, 32)!; assert key >= 61604 && key < 61716 && !seen[key]; seen[key] = true
	} }
	for count in 1 .. 17 { key := air_vector_float_key(.fma, count, 32)!; assert key == 61716 + count - 1 && !seen[key]; seen[key] = true }
	for id in [ScalarIntrinsic.air_fmin, .air_fmax]! { for count in 1 .. 17 { key := air_vector_float_key(id, count, 32)!; assert key == 61732 + int(id == .air_fmax) * 16 + count - 1 && !seen[key]; seen[key] = true } }
	for count in 1 .. 17 { key := air_vector_float_key(.air_clamp, count, 32)!; assert key == 61764 + count - 1 && !seen[key]; seen[key] = true }
	for id in [ScalarIntrinsic.smulh, .umulh]! { for count in 1 .. 17 { key := air_vector_intrinsic_key(id, count, 32)!; assert key == 61780 + int(id == .umulh) * 16 + count - 1 && !seen[key]; seen[key] = true } }
	for operation, id in [ScalarIntrinsic.sadd_sat, .ssub_sat, .uadd_sat, .usub_sat]! { for count in 1 .. 17 { key := air_vector_intrinsic_key(id, count, 32)!; assert key == 61812 + operation * 16 + count - 1 && !seen[key]; seen[key] = true } }
	for slot in seen { assert slot }
	for name in ['llvm.floor.f32', 'llvm.floor.v0f16', 'llvm.floor.v01f32', 'llvm.floor.v17f16', 'llvm.floor.v99999999999999999999f16', 'llvm.floor.v2f64', 'llvm.floor.v2bf16', 'llvm.floor.v2f016', 'llvm.floor.v2f32.spoof', 'llvm.floor.nxv2f32', 'llvm.roundeven.vf32', 'llvm.nearbyint.v2i32', 'llvm.sin.v2f32'] { if _, _, _ := vector_float_intrinsic_name(name) { assert false, name } }
	for id in [ScalarIntrinsic.fabs, .sqrt, .fma]! { if _ := rounding_intrinsic_vector(id, ScalarVectorValue{}, 32, 1) { assert false, 'family' } }
	for width in [u32(0), 1, 64]! { if _ := rounding_intrinsic_vector(.floor, ScalarVectorValue{}, width, 1) { assert false, 'width' } }
	for count in [0, 17] { if _ := rounding_intrinsic_vector(.floor, ScalarVectorValue{}, 16, count) { assert false, 'count' } }
	for tag in [IntegerValue{aggregate: true}, IntegerValue{vector: true}] { mut source := ScalarVectorValue{}; source.lanes[0] = tag; if _ := rounding_intrinsic_vector(.floor, source, 32, 1) { assert false, 'scalar tag' } }
	assert checks == 22848
	println('AIR-VECTOR-ROUND-STATES: ${checks} lane poison/undef/freeze checks; all 61876 floating/integer/conversion overload/cache identities and family/shape/name/tag guards PASS')
}
