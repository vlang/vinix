// SPDX-License-Identifier: GPL-2.0-or-later
module airbitcode

// Independent safe signed reconstruction; never negate a signed minimum.
fn vector_iabs_reference(value u64,width u32,flag u64) IntegerValue {
 x:=value&constant_mask(width);sign:=u64(1)<<(width-1)
 if x==sign{return if flag==1{IntegerValue{poison:true}}else{IntegerValue{value:sign}}}
 signed:=if x&sign==0{i64(x)}else{-i64((~x)&constant_mask(width))-1}
 return IntegerValue{value:u64(if signed<0{-signed}else{signed})}
}
fn test_vector_iabs_values_and_snapshots() {
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
   before := source; result := integer_abs_vector(source, width, count, flag)!
   for lane in 0 .. count { assert result.lanes[lane] == vector_iabs_reference(source.lanes[lane].value, width, flag); checks++ }
   assert source == before && result.undef == 0
  } }
 }
 }; assert checks == 1410048
 println('AIR-VECTOR-ABS-VALUES: ${checks} independent value/poison lane results, both minimum-poison flags, all 64 widths and 16 counts, zero/all-one/minimum/single-set/single-clear/mixed inputs, upper-bit masking and snapshots PASS')
}
fn test_vector_iabs_narrow_exhaustion_and_wide_patterns() {
 mut checks := 0
 for flag in u64(0) .. 2 { for width in u32(1) .. 65 {
  samples := if width <= 16 { int(u64(1) << width) } else { 4096 }
  for chunk in 0 .. (samples + 15) / 16 {
   mut source := ScalarVectorValue{}
   for lane in 0 .. 16 { k := (chunk * 16 + lane) % samples; x := if width <= 16 { u64(k) } else { (u64(k) * u64(0x9e3779b97f4a7c15)) ^ (u64(k) << 47) }; source.lanes[lane] = IntegerValue{value: x | ~constant_mask(width)} }
   result := integer_abs_vector(source, width, 16, flag)!
   for lane in 0 .. 16 { assert result.lanes[lane] == vector_iabs_reference(source.lanes[lane].value, width, flag); checks++ }
  }
 }
 }; assert checks == 655424
 println('AIR-VECTOR-ABS-SWEEP: ${checks} value/poison lanes covering every i1-i16 value and 4096 mixed patterns for every i17-i64 width PASS')
}
fn test_vector_iabs_states_and_names() {
 mut checks := 0; mut seen := [1024]bool{}
 for flag in u64(0) .. 2 { for width in u32(1) .. 65 { for count in 1 .. 17 {
  id, n, bits := vector_float_intrinsic_name('llvm.abs.v${count}i${width}')!; assert id == .iabs && n == count && bits == width
  key := vector_float_intrinsic_key(id, count, width)!; assert key >= 10944 && key < 11968 && (flag==1 || !seen[key - 10944]); seen[key - 10944] = true
  for target in 0 .. count {
   mut source := ScalarVectorValue{}; source.lanes[target] = IntegerValue{poison: true}; result := integer_abs_vector(source, width, count, flag)!
   for lane in 0 .. count { assert result.lanes[lane].poison == (lane == target); checks++ }; assert frozen_vector(result, count)!.lanes[target] == IntegerValue{}
   source.undef = u16(1) << u32(target); if _ := integer_abs_vector(source, width, count, flag) { assert false, 'undef dominates poison' }; checks++
  }
 } } }; for slot in seen { assert slot }; assert checks == 208896
 for name in ['llvm.abs.i32','llvm.abs.v0i32','llvm.abs.v01i32','llvm.abs.v17i32','llvm.abs.v999999999999i32','llvm.abs.v2i0','llvm.abs.v2i01','llvm.abs.v2i65','llvm.abs.v2i128','llvm.abs.v2i+1','llvm.abs.v2i1x','llvm.abs.v2i32.i32','llvm.abs.v2f32','llvm.abs.nxv2i32','air.abs.v2i32','llvm.sadd.sat.v2i32'] { if _, _, _ := vector_float_intrinsic_name(name) { assert false, name } }
 for flag in [u64(2),255,~u64(0)]! {if _:=integer_abs_vector(ScalarVectorValue{},32,1,flag){assert false,'flag'}}
 for width in [u32(0),65,128]! { if _ := integer_abs_vector(ScalarVectorValue{}, width, 1, 0) { assert false, 'width' } }
 for count in [0,17] { if _ := integer_abs_vector(ScalarVectorValue{}, 32, count, 0) { assert false, 'count' } }
 for tag in [IntegerValue{aggregate: true},IntegerValue{vector: true}] { mut source := ScalarVectorValue{}; source.lanes[0] = tag; if _ := integer_abs_vector(source, 32, 1, 0) { assert false, 'lane tag' } }
 println('AIR-VECTOR-ABS-STATES: ${checks} lane poison/undef/freeze checks, all 1024 overload/cache identities and name/shape/tag guards PASS')
}
