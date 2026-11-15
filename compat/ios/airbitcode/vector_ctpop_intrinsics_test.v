// SPDX-License-Identifier: GPL-2.0-or-later
module airbitcode

// Clear one set bit per iteration; production scans each declared bit instead.
fn vector_ctpop_reference(value u64, width u32) u64 {
 mut x := value & constant_mask(width); mut n := u64(0)
 for x != 0 { x &= x - 1; n++ }
 return n
}
fn test_vector_ctpop_values_and_snapshots() {
 mut checks := 0
 for width in u32(1) .. 65 {
  mask := constant_mask(width); sign := u64(1) << (width - 1)
  for count in 1 .. 17 { for sample in 0 .. int(width * 2 + 16) {
   mut source := ScalarVectorValue{}
   for lane in 0 .. count {
    k := (sample + lane) % int(width * 2 + 16)
    x := if k == 0 { u64(0) } else if k == 1 { mask } else if k == 2 { sign } else if k == 3 { sign - 1 } else if k < int(width) + 4 { u64(1) << u32(k - 4) } else if k < int(width) * 2 + 4 { mask ^ (u64(1) << u32(k - int(width) - 4)) } else { (u64(k) * u64(0x9e3779b97f4a7c15)) ^ (u64(k) << 47) }
    source.lanes[lane] = IntegerValue{value: x | ~mask}
   }
   before := source; result := ctpop_intrinsic_vector(source, width, count)!
   for lane in 0 .. count { assert result.lanes[lane] == IntegerValue{value: vector_ctpop_reference(source.lanes[lane].value, width)}; checks++ }
   assert source == before && result.undef == 0
  } }
 }
 assert checks == 705024
 println('AIR-VECTOR-CTPOP-VALUES: ${checks} independent exact lane values, all 64 widths and 16 counts, zero/all-one/sign/single-set/single-clear/mixed inputs, upper-bit masking and snapshots PASS')
}
fn test_vector_ctpop_narrow_exhaustion_and_wide_patterns() {
 mut checks := 0
 for width in u32(1) .. 65 {
  samples := if width <= 16 { int(u64(1) << width) } else { 4096 }
  for chunk in 0 .. (samples + 15) / 16 {
   mut source := ScalarVectorValue{}
   for lane in 0 .. 16 { k := (chunk * 16 + lane) % samples; x := if width <= 16 { u64(k) } else { (u64(k) * u64(0x9e3779b97f4a7c15)) ^ (u64(k) << 47) }; source.lanes[lane] = IntegerValue{value: x | ~constant_mask(width)} }
   result := ctpop_intrinsic_vector(source, width, 16)!
   for lane in 0 .. 16 { assert result.lanes[lane] == IntegerValue{value: vector_ctpop_reference(source.lanes[lane].value, width)}; checks++ }
  }
 }
 assert checks == 327712
 println('AIR-VECTOR-CTPOP-SWEEP: ${checks} exact lanes covering every i1-i16 value and 4096 mixed patterns for every i17-i64 width PASS')
}
fn test_vector_ctpop_states_and_names() {
 mut checks := 0; mut seen := [1024]bool{}
 for width in u32(1) .. 65 { for count in 1 .. 17 {
  id, n, bits := vector_float_intrinsic_name('llvm.ctpop.v${count}i${width}')!; assert id == .ctpop && n == count && bits == width
  key := vector_float_intrinsic_key(id, count, width)!; assert key >= 640 && key < 1664 && !seen[key - 640]; seen[key - 640] = true
  for target in 0 .. count {
   mut source := ScalarVectorValue{}; source.lanes[target] = IntegerValue{poison: true}; result := ctpop_intrinsic_vector(source, width, count)!
   for lane in 0 .. count { assert result.lanes[lane].poison == (lane == target); checks++ }; assert frozen_vector(result, count)!.lanes[target] == IntegerValue{}
   source.undef = u16(1) << u32(target); if _ := ctpop_intrinsic_vector(source, width, count) { assert false, 'undef dominates poison' }; checks++
  }
 } }; for slot in seen { assert slot }; assert checks == 104448
 for name in ['llvm.ctpop.i32','llvm.ctpop.v0i32','llvm.ctpop.v01i32','llvm.ctpop.v17i32','llvm.ctpop.v999999999999i32','llvm.ctpop.v2i0','llvm.ctpop.v2i01','llvm.ctpop.v2i65','llvm.ctpop.v2i128','llvm.ctpop.v2i+1','llvm.ctpop.v2i1x','llvm.ctpop.v2i32.i32','llvm.ctpop.v2f32','llvm.ctpop.nxv2i32','air.ctpop.v2i32','llvm.bswap.v2i32'] { if _, _, _ := vector_float_intrinsic_name(name) { assert false, name } }
 for width in [u32(0),65,128]! { if _ := ctpop_intrinsic_vector(ScalarVectorValue{}, width, 1) { assert false, 'width' } }
 for count in [0,17] { if _ := ctpop_intrinsic_vector(ScalarVectorValue{}, 32, count) { assert false, 'count' } }
 for tag in [IntegerValue{aggregate: true},IntegerValue{vector: true}] { mut source := ScalarVectorValue{}; source.lanes[0] = tag; if _ := ctpop_intrinsic_vector(source, 32, 1) { assert false, 'lane tag' } }
 println('AIR-VECTOR-CTPOP-STATES: ${checks} lane poison/undef/freeze checks, all 1024 overload/cache identities and name/shape/tag guards PASS')
}
