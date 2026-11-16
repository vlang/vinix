// SPDX-License-Identifier: GPL-2.0-or-later
module airbitcode

fn test_stepvector_values_names_and_cache() {
 mut seen:=[912]bool{};mut lanes:=0
 for bits in u32(8)..65 {for count in 1..17 {
  name:='llvm.stepvector.v${count}i${bits}';n,b:=vector_step_name(name)!;assert n==count&&b==bits
  id,actual,width:=vector_float_intrinsic_name(name)!;assert id==.stepvector&&actual==count&&width==bits&&scalar_intrinsic_arity(id)==0
  key:=vector_step_key(count,bits)!;assert key==41716+(int(bits)-8)*16+count-1&&!seen[key-41716];seen[key-41716]=true
  result:=step_vector(count,bits)!;assert result.undef==0
  for lane in 0..count {assert result.lanes[lane]==IntegerValue{value:u64(lane)};lanes++}
  for lane in count..16 {assert result.lanes[lane]==IntegerValue{}}
  if _:=scalar_intrinsic_name(name) {assert false}
 }}
 for value in seen {assert value}
 assert lanes==7752
 for name in ['llvm.stepvector.v0i32','llvm.stepvector.v17i32','llvm.stepvector.v01i32','llvm.stepvector.v2i1','llvm.stepvector.v2i7','llvm.stepvector.v2i65','llvm.stepvector.v2f16','llvm.stepvector.v2f32','llvm.stepvector.nxv2i32','llvm.stepvector.v2i32.spoof','llvm.stepvector.i32','llvm.stepvector.v999999999999999999i32'] {if _,_:=vector_step_name(name) {assert false,name}}
 for count in [0,17] {if _:=step_vector(count,32) {assert false}}
 for bits in [u32(0),7,65] {if _:=step_vector(1,bits) {assert false}}
 println('AIR-STEPVECTOR-UNIT: 912 zero-argument overload/key identities, 7752 defined lane values, clear state/unused lanes and canonical shape/name guards PASS')
}
