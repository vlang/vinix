// SPDX-License-Identifier: GPL-2.0-or-later
module airbitcode

fn test_air_float_names_slots_and_existing_evaluators() {
	assert scalar_air_float_cache_base == 2168 && scalar_intrinsic_cache_slots == 2200
	ids := [ScalarIntrinsic.fabs, .floor, .ceil, .trunc, .sqrt, .round, .rint]!
	for i, name in ['air.fabs.f32', 'air.floor.f32', 'air.ceil.f32', 'air.trunc.f32', 'air.sqrt.f32', 'air.round.f32', 'air.rint.f32'] {
		id, slot := air_float_intrinsic(name)!
		assert id == ids[i] && slot == i && scalar_intrinsic_name(name)! == id
		assert scalar_intrinsic_arity(id) == 1 && !scalar_integer_intrinsic(id)
		if _, _ := air_integer_intrinsic(name) { assert false }
	}
	for name in ['air.fabs.f64', 'air.floor.f64', 'air.ceil.v2f32', 'air.trunc.i32', 'air.floor.f032', 'air.floor.f+32', 'air.floor.f32.spoof', 'air.fast_floor.f32', 'air.rsqrt.f32', 'air.sin.f32', 'air.sqrt.f64', 'air.sqrt.v2f32', 'air.fast_sqrt.f32', 'air.round.f64', 'air.round.f032', 'air.roundeven.f32', 'air.rint.f64', 'air.rint.f32.spoof'] {
		if _ := scalar_intrinsic_name(name) { assert false, name }
	}
	assert scalar_intrinsic_value(.fabs, 32, 0xff812345, 0)! == 0x7f812345
	assert scalar_intrinsic_value(.floor, 32, 0x80000001, 0)! == 0xbf800000
	assert scalar_intrinsic_value(.ceil, 32, 1, 0)! == 0x3f800000
	assert scalar_intrinsic_value(.trunc, 32, 0x80000001, 0)! == 0x80000000
	assert scalar_intrinsic_value(.sqrt, 32, 0x40000000, 0)! == 0x3fb504f3
	assert scalar_intrinsic_value(.sqrt, 32, 0x80000000, 0)! == 0x80000000
	assert scalar_intrinsic_value(.sqrt, 32, 0x80000001, 0)! == 0x7fc00000
	for sign in [u64(0),0x80000000]! {
		assert scalar_intrinsic_value(.round, 32, sign|0x3f000000, 0)! == sign|0x3f800000
		assert scalar_intrinsic_value(.rint, 32, sign|0x3f000000, 0)! == sign
		assert scalar_intrinsic_value(.round, 32, sign|0x40200000, 0)! == sign|0x40400000
		assert scalar_intrinsic_value(.rint, 32, sign|0x40200000, 0)! == sign|0x40000000
	}
	println('AIR-FLOAT-NAMES: seven exact f32 names, appended slots, unary identities, bit/rounding/root boundaries and width/vector/family/spelling guards PASS')
}

fn test_air_float_fma_name_slot_and_ternary_identity() {
	id, slot := air_float_intrinsic('air.fma.f32')!
	assert id == .fma && slot == 7 && scalar_air_float_cache_base + slot == 2175
	assert scalar_intrinsic_name('air.fma.f32')! == id && scalar_intrinsic_arity(id) == 3
	assert !scalar_integer_intrinsic(id)
	if _, _ := air_integer_intrinsic('air.fma.f32') { assert false }
	for name in ['air.fma.f16','air.fma.f64','air.fma.v2f32','air.fma.i32','air.fma.f032','air.fma.f+32','air.fma.f32.spoof','air.fast_fma.f32','air.fmuladd.f32'] {
		if _ := scalar_intrinsic_name(name) { assert false, name }
	}
	assert scalar_fma(32, 0x3f800001, 0x3f7ffffe, 0xbf800000)! == 0xa8800000
	assert scalar_fma(32, 0x7f7fffff, 0x40000000, 0xff7fffff)! == 0x7f7fffff
	assert scalar_fma(32, 1, 0x3f000000, 1)! == 2
	println('AIR-FMA-NAME: exact f32 ternary identity, appended slot, fused cancellation/overflow/underflow and unsupported overload/name guards PASS')
}

// Rational binary16 oracle, independent of the evaluator's fraction-bit masks.
fn air_half_unary_reference(id ScalarIntrinsic, raw u64) u64 {
 if id == .fabs { return raw & 0x7fff }
 sign := raw & 0x8000; a := raw & 0x7fff
 if a > 0x7c00 { return 0x7e00 }
 if a == 0x7c00 || a == 0 { return raw }
 e := int(a >> 10); shift := if e == 0 { 24 } else { 25 - e }
 if shift <= 0 { return raw }
 numerator := if e == 0 { a } else { 1024 + (a & 1023) }; denominator := u64(1) << u32(shift)
 mut integer := numerator / denominator; remainder := numerator % denominator
 if (id == .floor && sign != 0 && remainder != 0) || (id == .ceil && sign == 0 && remainder != 0) || (id == .round && remainder * 2 >= denominator) || (id == .rint && (remainder * 2 > denominator || (remainder * 2 == denominator && integer % 2 == 1))) { integer++ }
 if integer == 0 { return sign }
 mut exponent := 0; for (u64(1) << u32(exponent + 1)) <= integer { exponent++ }
 fraction := if exponent <= 10 { (integer - (u64(1) << u32(exponent))) << u32(10 - exponent) } else { (integer - (u64(1) << u32(exponent))) >> u32(exponent - 10) }
 return sign | (u64(exponent + 15) << 10) | fraction
}
fn test_air_half_unary_names_cache_and_every_encoding() {
 assert scalar_air_half_float_cache_base == 2193 && scalar_intrinsic_cache_slots == 2200
 mut checks := 0
 for i, family in ['fabs','floor','ceil','trunc'] {
  name := 'air.${family}.f16'; id, slot := air_float_intrinsic(name)!
  old_id, old_slot := air_float_intrinsic('air.${family}.f32')!
  assert scalar_intrinsic_name(name)! == id && id == old_id && scalar_intrinsic_arity(id) == 1
  assert scalar_air_float_cache_base + slot == 2193 + i && scalar_air_float_cache_base + old_slot == 2168 + i
  assert !scalar_integer_intrinsic(id)
  for raw in 0..65536 {
   expected := air_half_unary_reference(id,u64(raw))
   assert scalar_intrinsic_value(id,16,u64(raw)|~u64(0xffff),0)! == expected
   checks++
  }
  for suffix in ['f016','f+16','f16.spoof','v2f16','f64','i16'] {
   if _ := scalar_intrinsic_name('air.${family}.${suffix}') { assert false }
  }
 }
 for family in ['fma','fmin','fmax','clamp','fast_fabs','fast_floor'] {
  if _ := scalar_intrinsic_name('air.${family}.f16') { assert false }
 }
 assert checks == 262144
 println('AIR-HALF-UNARY: four exact identities, stable f32 keys, appended half keys, 262144 independent rational/bit values across every binary16 encoding, high-bit masking and name/family guards PASS')
}

// Exact binary16 value in units of 2^-24, for squared-midpoint comparisons.
fn air_sqrt_half_units(raw u64) u64 {
 e := int(raw >> 10)
 return if e == 0 { raw } else { (1024 + (raw & 1023)) << u32(e - 1) }
}
fn test_air_half_math_names_cache_and_every_encoding() {
 assert scalar_air_half_float_cache_base == 2193 && scalar_intrinsic_cache_slots == 2200
 mut checks := 0
 for i, family in ['sqrt','round','rint'] {
  name := 'air.${family}.f16'; id, slot := air_float_intrinsic(name)!
  old_id, old_slot := air_float_intrinsic('air.${family}.f32')!
  assert scalar_intrinsic_name(name)! == id && id == old_id && scalar_intrinsic_arity(id) == 1
  assert scalar_air_float_cache_base + slot == 2197 + i && scalar_air_float_cache_base + old_slot == 2172 + i
  assert !scalar_integer_intrinsic(id)
  for raw in 0..65536 {
   x := u64(raw); y := scalar_intrinsic_value(id,16,x|~u64(0xffff),0)!
   if id != .sqrt { assert y == air_half_unary_reference(id,x) }
   else if x & 0x7fff == 0 { assert y == x }
   else if x > 0x7c00 { assert y == 0x7e00 }
   else if x == 0x7c00 { assert y == x }
   else {
    assert y >= 0x0c00 && y <= 0x5bff
    center := air_sqrt_half_units(y)
    lower := (air_sqrt_half_units(y-1) + center) / 2
    upper := (air_sqrt_half_units(y+1) + center) / 2
    target := air_sqrt_half_units(x) << 24; even := y & 1 == 0
    assert target > lower * lower || (target == lower * lower && even)
    assert target < upper * upper || (target == upper * upper && even)
   }
   checks++
  }
  for suffix in ['f016','f+16','f16.spoof','v2f16','f64','i16'] {
   if _ := scalar_intrinsic_name('air.${family}.${suffix}') { assert false }
  }
 }
 for name in ['air.fast_sqrt.f16','air.rsqrt.f16','air.roundeven.f16','air.nearbyint.f16','air.fast_round.f16','air.fast_rint.f16'] {
  if _ := scalar_intrinsic_name(name) { assert false }
 }
 assert checks == 196608
 for raw in [u64(0),0x80000000,0x7f800000,0xff800000]! {
  expected := if raw == 0xff800000 { u64(0x7fc00000) } else { raw }
  assert scalar_intrinsic_value(.sqrt,32,raw|~u64(0xffffffff),0)! == expected
 }
 println('AIR-HALF-MATH: three exact identities, stable previous keys, 196608 independent rational/squared-midpoint checks across every binary16 encoding, high-bit masking and name/family guards PASS')
}
