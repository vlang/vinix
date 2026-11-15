// SPDX-License-Identifier: GPL-2.0-or-later
module airbitcode
import math.bits as bitops

// Independent standard-library count, adjusted for the declared width.
fn vector_ctlz_reference(value u64,width u32,flag u64) IntegerValue {
 x:=value&constant_mask(width);return if x==0&&flag==1 {IntegerValue{poison:true}}else{IntegerValue{value:u64(bitops.leading_zeros_64(x))-u64(64-width)}}
}
fn test_vector_ctlz_values_and_snapshots() {
 mut checks := 0
 for flag in u64(0) .. 2 { for width in u32(1) .. 65 {
  mask := constant_mask(width); sign := u64(1) << (width - 1)
  for count in 1 .. 17 { for sample in 0 .. int(width * 2 + 16) {
   mut source := ScalarVectorValue{}
   for lane in 0 .. count {
    k := (sample + lane) % int(width * 2 + 16)
    x := if k == 0 { u64(0) } else if k == 1 { mask } else if k == 2 { sign } else if k == 3 { sign - 1 } else if k < int(width) + 4 { u64(1) << u32(k - 4) } else if k < int(width) * 2 + 4 { mask ^ (u64(1) << u32(k - int(width) - 4)) } else { (u64(k) * u64(0x9e3779b97f4a7c15)) ^ (u64(k) << 47) }
    source.lanes[lane] = IntegerValue{value: x | ~mask}
   }
   before := source; result := zero_count_intrinsic_vector(.ctlz, source, width, count, flag)!
   for lane in 0 .. count { assert result.lanes[lane] == vector_ctlz_reference(source.lanes[lane].value, width, flag); checks++ }
   assert source == before && result.undef == 0
  } }
 }
 }; assert checks == 1410048
 println('AIR-VECTOR-CTLZ-VALUES: ${checks} independent value/poison lane results, both flags, all 64 widths and 16 counts, zero/all-one/sign/single-set/single-clear/mixed inputs, upper-bit masking and snapshots PASS')
}
fn test_vector_ctlz_narrow_exhaustion_and_wide_patterns() {
 mut checks := 0
 for flag in u64(0) .. 2 { for width in u32(1) .. 65 {
  samples := if width <= 16 { int(u64(1) << width) } else { 4096 }
  for chunk in 0 .. (samples + 15) / 16 {
   mut source := ScalarVectorValue{}
   for lane in 0 .. 16 { k := (chunk * 16 + lane) % samples; x := if width <= 16 { u64(k) } else { (u64(k) * u64(0x9e3779b97f4a7c15)) ^ (u64(k) << 47) }; source.lanes[lane] = IntegerValue{value: x | ~constant_mask(width)} }
   result := zero_count_intrinsic_vector(.ctlz, source, width, 16, flag)!
   for lane in 0 .. 16 { assert result.lanes[lane] == vector_ctlz_reference(source.lanes[lane].value, width, flag); checks++ }
  }
 }
 }; assert checks == 655424
 println('AIR-VECTOR-CTLZ-SWEEP: ${checks} value/poison lanes covering every i1-i16 value and 4096 mixed patterns for every i17-i64 width PASS')
}
fn test_vector_ctlz_states_and_names() {
 mut checks := 0; mut seen := [1024]bool{}
 for flag in u64(0) .. 2 { for width in u32(1) .. 65 { for count in 1 .. 17 {
  id, n, bits := vector_float_intrinsic_name('llvm.ctlz.v${count}i${width}')!; assert id == .ctlz && n == count && bits == width
  key := vector_float_intrinsic_key(id, count, width)!; assert key >= 2752 && key < 3776 && (flag==1 || !seen[key - 2752]); seen[key - 2752] = true
  for target in 0 .. count {
   mut source := ScalarVectorValue{}; for lane in 0 .. count {source.lanes[lane]=IntegerValue{value:1}}; source.lanes[target] = IntegerValue{poison: true}; result := zero_count_intrinsic_vector(.ctlz, source, width, count, flag)!
   for lane in 0 .. count { assert result.lanes[lane].poison == (lane == target); checks++ }; assert frozen_vector(result, count)!.lanes[target] == IntegerValue{}
   source.undef = u16(1) << u32(target); if _ := zero_count_intrinsic_vector(.ctlz, source, width, count, flag) { assert false, 'undef dominates poison' }; checks++
  }
 } } }; for slot in seen { assert slot }; assert checks == 208896
 for name in ['llvm.ctlz.i32','llvm.ctlz.v0i32','llvm.ctlz.v01i32','llvm.ctlz.v17i32','llvm.ctlz.v999999999999i32','llvm.ctlz.v2i0','llvm.ctlz.v2i01','llvm.ctlz.v2i65','llvm.ctlz.v2i128','llvm.ctlz.v2i+1','llvm.ctlz.v2i1x','llvm.ctlz.v2i32.i32','llvm.ctlz.v2f32','llvm.ctlz.nxv2i32','air.ctlz.v2i32','llvm.fshl.v2i32'] { if _, _, _ := vector_float_intrinsic_name(name) { assert false, name } }
 for flag in [u64(2),255,~u64(0)]! {if _:=zero_count_intrinsic_vector(.ctlz,ScalarVectorValue{},32,1,flag){assert false,'flag'}}
 for width in [u32(0),65,128]! { if _ := zero_count_intrinsic_vector(.ctlz, ScalarVectorValue{}, width, 1, 0) { assert false, 'width' } }
 for count in [0,17] { if _ := zero_count_intrinsic_vector(.ctlz, ScalarVectorValue{}, 32, count, 0) { assert false, 'count' } }
 for tag in [IntegerValue{aggregate: true},IntegerValue{vector: true}] { mut source := ScalarVectorValue{}; source.lanes[0] = tag; if _ := zero_count_intrinsic_vector(.ctlz, source, 32, 1, 0) { assert false, 'lane tag' } }
 println('AIR-VECTOR-CTLZ-STATES: ${checks} lane poison/undef/freeze checks, all 1024 overload/cache identities and name/shape/tag guards PASS')
}
