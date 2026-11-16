// SPDX-License-Identifier: GPL-2.0-or-later
module airbitcode

fn test_vector_interleave_raw_lanes_states_snapshots() {
 mut checks:=0
 for factor in 2..9 {for count in 1..16/factor+1 {for sample in u64(0)..4096 {
  mut sources:=[8]ScalarVectorValue{}
  for input in 0..factor {for lane in 0..count {
   sources[input].lanes[lane]=IntegerValue{value:sample*u64(0x9e3779b97f4a7c15)+u64(input*23+lane),poison:(int(sample)+input+lane)%7==0}
   if (int(sample)+input*3+lane)%11==0 {sources[input].undef|=u16(1)<<u32(lane)}
  }}
  before:=sources;result:=interleaved_vector(sources,factor,count)!
  for lane in 0..factor*count {input:=lane%factor;index:=lane/factor;assert result.lanes[lane]==before[input].lanes[index];assert (result.undef>>u32(lane))&1==(before[input].undef>>u32(index))&1;checks++}
  assert before==sources
 }}}
 assert checks==1024000
 println('AIR-VECTOR-INTERLEAVE-VALUES: ${checks} raw lane/state comparisons, all factors/counts, source snapshots PASS')
}
fn test_vector_interleave_names_keys_and_guards() {
 mut seen:=[1716]bool{}
 for id in [ScalarIntrinsic.vector_interleave2,.vector_interleave3,.vector_interleave4,.vector_interleave5,.vector_interleave6,.vector_interleave7,.vector_interleave8]! {
  factor:=scalar_intrinsic_arity(id)
  for count in 1..16/factor+1 {for format in 0..66 {
   suffix:=if format<64 {'i${format+1}'}else if format==64 {'f16'}else{'f32'};name:='llvm.vector.interleave${factor}.v${factor*count}${suffix}'
   actual,n,f:=vector_interleave_name(name)!;assert actual==id&&n==factor*count&&f==format
   parsed,lanes,width:=vector_float_intrinsic_name(name)!;assert parsed==id&&lanes==n&&width==if format<64 {u32(format+1)}else if format==64 {u32(16)}else{u32(32)}
   key:=vector_interleave_key(id,n,format)!;assert key>=40000&&key<41716&&!seen[key-40000];seen[key-40000]=true
   if _:=scalar_intrinsic_name(name) {assert false}
  }}
 }
 for value in seen {assert value}
 for name in ['llvm.vector.interleave1.v2i32','llvm.vector.interleave9.v9i32','llvm.vector.interleave02.v4i32','llvm.vector.interleave2.v0i32','llvm.vector.interleave2.v3i32','llvm.vector.interleave8.v8i0','llvm.vector.interleave2.v18i32','llvm.vector.interleave2.v04i32','llvm.vector.interleave2.v4i65','llvm.vector.interleave2.nxv4i32','llvm.vector.interleave2.v4f64','llvm.vector.interleave2.v4bf16','llvm.vector.interleave2.v4i32.spoof','llvm.vector.interleave2.v99999999999999999999i32'] {if _,_,_:=vector_interleave_name(name) {assert false,name}}
 for factor in [0,1,9] {if _:=interleaved_vector([8]ScalarVectorValue{},factor,1) {assert false}}
 for count in [0,9] {if _:=interleaved_vector([8]ScalarVectorValue{},2,count) {assert false}}
 for tag in [IntegerValue{aggregate:true},IntegerValue{vector:true}] {mut sources:=[8]ScalarVectorValue{};sources[1].lanes[0]=tag;if _:=interleaved_vector(sources,2,1) {assert false}}
 for format in [-1,66] {if _:=vector_interleave_key(.vector_interleave2,2,format) {assert false}}
 if _:=vector_interleave_key(.vector_reverse,2,0) {assert false}
 if _:=vector_interleave_key(.vector_interleave3,4,0) {assert false}
 println('AIR-VECTOR-INTERLEAVE-NAMES: 1716 overload/key identities and canonical name/family/count/tag guards PASS')
}
