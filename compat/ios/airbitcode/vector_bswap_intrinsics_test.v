// SPDX-License-Identifier: GPL-2.0-or-later
module airbitcode
import math.bits as bitops

// Reverse all eight bytes with the standard library, then select the declared width.
fn vector_bswap_reference(value u64, width u32) u64 {
 return bitops.reverse_bytes_64(value & constant_mask(width)) >> (64 - width)
}
fn test_vector_bswap_values_and_snapshots() {
 mut checks := 0
 for width in [u32(16),32,48,64]! {
  mask := constant_mask(width); sign := u64(1) << (width - 1)
  for count in 1 .. 17 { for sample in 0 .. int(width * 2 + 16) {
   mut source := ScalarVectorValue{}
   for lane in 0 .. count {
    k := (sample + lane) % int(width * 2 + 16)
    x := if k == 0 { u64(0) } else if k == 1 { mask } else if k == 2 { sign } else if k == 3 { sign - 1 } else if k < int(width) + 4 { u64(1) << u32(k - 4) } else if k < int(width) * 2 + 4 { mask ^ (u64(1) << u32(k - int(width) - 4)) } else { (u64(k) * u64(0x9e3779b97f4a7c15)) ^ (u64(k) << 47) }
    source.lanes[lane] = IntegerValue{value: x | ~mask}
   }
   before := source; result := integer_intrinsic_vector(.bswap, source, width, count)!
   for lane in 0 .. count { assert result.lanes[lane] == IntegerValue{value: vector_bswap_reference(source.lanes[lane].value, width)}; checks++ }
   assert source == before && result.undef == 0
   restored := integer_intrinsic_vector(.bswap, result, width, count)!
   for lane in 0 .. count { assert restored.lanes[lane] == IntegerValue{value: source.lanes[lane].value & mask} }
  } }
 }
 assert checks == 52224
 println('AIR-VECTOR-BSWAP-VALUES: ${checks} independent exact lane values and involutions, all four widths and 16 counts, zero/all-one/sign/single-set/single-clear/mixed inputs, upper-bit masking and snapshots PASS')
}
fn test_vector_bswap_narrow_exhaustion_and_wide_patterns() {
 mut checks := 0
 for width in [u32(16),32,48,64]! {
  samples := if width <= 16 { int(u64(1) << width) } else { 4096 }
  for chunk in 0 .. (samples + 15) / 16 {
   mut source := ScalarVectorValue{}
   for lane in 0 .. 16 { k := (chunk * 16 + lane) % samples; x := if width <= 16 { u64(k) } else { (u64(k) * u64(0x9e3779b97f4a7c15)) ^ (u64(k) << 47) }; source.lanes[lane] = IntegerValue{value: x | ~constant_mask(width)} }
   result := integer_intrinsic_vector(.bswap, source, width, 16)!
   for lane in 0 .. 16 { assert result.lanes[lane] == IntegerValue{value: vector_bswap_reference(source.lanes[lane].value, width)}; checks++ }
  }
 }
 assert checks == 77824
 println('AIR-VECTOR-BSWAP-SWEEP: ${checks} exact lanes covering every i16 value and 4096 mixed patterns for i32/i48/i64 PASS')
}
fn test_vector_bswap_states_and_names() {
 mut checks := 0; mut seen := [64]bool{}
 for width in [u32(16),32,48,64]! { for count in 1 .. 17 {
  id, n, bits := vector_float_intrinsic_name('llvm.bswap.v${count}i${width}')!; assert id == .bswap && n == count && bits == width
  key := vector_float_intrinsic_key(id, count, width)!; assert key >= 2688 && key < 2752 && !seen[key - 2688]; seen[key - 2688] = true
  for target in 0 .. count {
   mut source := ScalarVectorValue{}; source.lanes[target] = IntegerValue{poison: true}; result := integer_intrinsic_vector(.bswap, source, width, count)!
   for lane in 0 .. count { assert result.lanes[lane].poison == (lane == target); checks++ }; assert frozen_vector(result, count)!.lanes[target] == IntegerValue{}
   source.undef = u16(1) << u32(target); if _ := integer_intrinsic_vector(.bswap, source, width, count) { assert false, 'undef dominates poison' }; checks++
  }
 } }; for slot in seen { assert slot }; assert checks == 6528
 for name in ['llvm.bswap.i32','llvm.bswap.v0i32','llvm.bswap.v01i32','llvm.bswap.v17i32','llvm.bswap.v999999999999i32','llvm.bswap.v2i0','llvm.bswap.v2i01','llvm.bswap.v2i65','llvm.bswap.v2i128','llvm.bswap.v2i1','llvm.bswap.v2i8','llvm.bswap.v2i24','llvm.bswap.v2i40','llvm.bswap.v2i56','llvm.bswap.v2i+1','llvm.bswap.v2i1x','llvm.bswap.v2i32.i32','llvm.bswap.v2f32','llvm.bswap.nxv2i32','air.bswap.v2i32','llvm.sadd.sat.v2i32'] { if _, _, _ := vector_float_intrinsic_name(name) { assert false, name } }
 for id in [ScalarIntrinsic.ctlz, .fabs, .sqrt]! { if _ := integer_intrinsic_vector(id, ScalarVectorValue{}, 32, 1) { assert false, 'family' } }
 for width in [u32(0),1,8,24,40,56,65,128]! { if _ := integer_intrinsic_vector(.bswap, ScalarVectorValue{}, width, 1) { assert false, 'width' } }
 for count in [0,17] { if _ := integer_intrinsic_vector(.bswap, ScalarVectorValue{}, 32, count) { assert false, 'count' } }
 for tag in [IntegerValue{aggregate: true},IntegerValue{vector: true}] { mut source := ScalarVectorValue{}; source.lanes[0] = tag; if _ := integer_intrinsic_vector(.bswap, source, 32, 1) { assert false, 'lane tag' } }
 println('AIR-VECTOR-BSWAP-STATES: ${checks} lane poison/undef/freeze checks, all 64 overload/cache identities and name/shape/tag guards PASS')
}
