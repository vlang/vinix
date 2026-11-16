// SPDX-License-Identifier: GPL-2.0-or-later
module airbitcode

// Independent ordering of raw encodings; NaNs are detected before selecting
// the extrema. A one-lane reduction is the identity.
fn float_reduction_reference(maximum bool, bits u32, words [16]u64, count int) u64 {
 mask:=constant_mask(bits);sign:=u64(1)<<(bits-1);infinity:=if bits==16 {u64(0x7c00)} else {u64(0x7f800000)}
 if count==1 {return words[0]&mask}
 mut chosen:=u64(0);mut best:=u64(0)
 for i in 0..count {x:=words[i]&mask;if x&(sign-1)>infinity {return if bits==16 {u64(0x7e00)} else {u64(0x7fc00000)}};key:=if x&sign!=0 {~x&mask} else {x|sign};if i==0||(maximum&&key>best)||(!maximum&&key<best) {chosen=x;best=key}}
 return chosen
}
fn test_float_reduction_values(){
 mut checks:=0
 for bits in [u32(16),32]! {for sample in 0..65536 {for count in 1..17 {
  mut source:=ScalarVectorValue{};mut words:=[16]u64{}
  for lane in 0..count {words[lane]=(if bits==16 {u64((sample+lane)%65536)} else {u64(u32(sample)*u32(0x9e3779b9)+u32(lane)*u32(0x01010101))})|~constant_mask(bits);source.lanes[lane]=IntegerValue{value:words[lane]}}
  before:=source
  for id in [ScalarIntrinsic.minimum,.maximum]! {result:=reduced_floating_vector(id,source,bits,count)!;assert result==IntegerValue{value:float_reduction_reference(id==.maximum,bits,words,count)};assert source==before;checks++}
 }}}
 assert checks==4194304
 println('AIR-FLOAT-REDUCTION-VALUES: ${checks} independent ordered-key values, all half encodings/deterministic float patterns, both operations and every count, one-lane identity, upper-bit masks and snapshots PASS')
}
fn test_float_reduction_states(){
 mut checks:=0
 for bits in [u32(16),32]! {for id in [ScalarIntrinsic.minimum,.maximum]! {for count in 1..17 {for target in 0..count {
  mut source:=ScalarVectorValue{};source.lanes[target]=IntegerValue{poison:true}
  assert reduced_floating_vector(id,source,bits,count)!.poison;checks++
  source.undef=u16(1)<<u32(target);if _:=reduced_floating_vector(id,source,bits,count) {assert false};checks++
 }if count>1 {mut source:=ScalarVectorValue{};source.lanes[0]=IntegerValue{poison:true};source.undef=u16(1)<<u32(count-1);if _:=reduced_floating_vector(id,source,bits,count) {assert false};checks++}}}}
 assert checks==1148
 for name in ['llvm.vector.reduce.fminimum.v0f16','llvm.vector.reduce.fmaximum.v01f32','llvm.vector.reduce.fminimum.v17f32','llvm.vector.reduce.fmaximum.v2f64','llvm.vector.reduce.fminimum.v2i32','llvm.vector.reduce.fminimum.nxv2f32','llvm.vector.reduce.fminimum.v2f32.spoof','llvm.vector.reduce.fmin.v2f32','llvm.vector.reduce.fminimumnum.v2f32'] {if _,_,_:=floating_vector_reduction_name(name) {assert false,name}}
 for id in [ScalarIntrinsic.floor,.minimumnum,.maximum]! {if id==.maximum {continue};if _:=reduced_floating_vector(id,ScalarVectorValue{},32,1) {assert false}}
 for bits in [u32(0),1,64]! {if _:=reduced_floating_vector(.minimum,ScalarVectorValue{},bits,1) {assert false}}
 for count in [0,17] {if _:=reduced_floating_vector(.maximum,ScalarVectorValue{},32,count) {assert false}}
 for tag in [IntegerValue{aggregate:true},IntegerValue{vector:true}] {mut source:=ScalarVectorValue{};source.lanes[0]=tag;if _:=reduced_floating_vector(.minimum,source,32,1) {assert false}}
 println('AIR-FLOAT-REDUCTION-STATES: ${checks} all-lane poison/undef and mixed-state checks, name/shape/family/tag guards PASS')
}
