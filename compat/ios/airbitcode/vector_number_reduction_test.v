// SPDX-License-Identifier: GPL-2.0-or-later
module airbitcode

// Independent ordering of raw encodings; NaNs are detected before selecting
// the numeric extrema, ignoring both NaN classes. A one-lane reduction is the identity.
fn number_reduction_reference(maximum bool, bits u32, words [16]u64, count int) u64 {
 lane_mask:=if bits==16 {u64(0xffff)} else {u64(0xffffffff)};sign:=u64(1)<<(bits-1);infinity:=if bits==16 {u64(0x7c00)} else {u64(0x7f800000)}
 if count==1 {return words[0]&lane_mask}
 mut chosen:=if bits==16 {u64(0x7e00)} else {u64(0x7fc00000)};mut best:=u64(0);mut found:=false
 for i in 0..count {x:=words[i]&lane_mask;if x&(sign-1)>infinity {continue};key:=if x&sign!=0 {~x&lane_mask} else {x|sign};if !found||(maximum&&key>best)||(!maximum&&key<best) {chosen=x;best=key;found=true}}
 return chosen
}
fn test_number_reduction_values(){
 mut checks:=0
 for bits in [u32(16),32]! {for sample in 0..65536 {for count in 1..17 {
  mut source:=ScalarVectorValue{};mut words:=[16]u64{}
  for lane in 0..count {words[lane]=(if bits==16 {u64((sample+lane)%65536)} else {u64(u32(sample)*u32(0x9e3779b9)+u32(lane)*u32(0x01010101))})|~constant_mask(bits);source.lanes[lane]=IntegerValue{value:words[lane]}}
  before:=source
  for id in [ScalarIntrinsic.minnum,.maxnum]! {result:=reduced_floating_vector(id,source,bits,count)!;assert result==IntegerValue{value:number_reduction_reference(id==.maxnum,bits,words,count)};assert source==before;checks++}
 }}}
 assert checks==4194304
 println('AIR-NUMBER-REDUCTION-VALUES: ${checks} independent NaN-skipping ordered-key values, all half encodings/deterministic float patterns, both operations and every count, one-lane identity, upper-bit masks and snapshots PASS')
}
fn test_number_reduction_states(){
 mut checks:=0
 for bits in [u32(16),32]! {for id in [ScalarIntrinsic.minnum,.maxnum]! {for count in 1..17 {for target in 0..count {
  mut source:=ScalarVectorValue{};source.lanes[target]=IntegerValue{poison:true}
  assert reduced_floating_vector(id,source,bits,count)!.poison;checks++
  source.undef=u16(1)<<u32(target);if _:=reduced_floating_vector(id,source,bits,count) {assert false};checks++
 }if count>1 {mut source:=ScalarVectorValue{};source.lanes[0]=IntegerValue{poison:true};source.undef=u16(1)<<u32(count-1);if _:=reduced_floating_vector(id,source,bits,count) {assert false};checks++}}}}
 assert checks==1148
 for name in ['llvm.vector.reduce.fmin.v0f16','llvm.vector.reduce.fmax.v01f32','llvm.vector.reduce.fmin.v17f32','llvm.vector.reduce.fmax.v2f64','llvm.vector.reduce.fmin.v2i32','llvm.vector.reduce.fmin.nxv2f32','llvm.vector.reduce.fmin.v2f32.spoof','llvm.vector.reduce.fminimum.v2f32','llvm.vector.reduce.fmaxnum.v2f32'] {if _,_,_:=number_vector_reduction_name(name) {assert false,name}}
 for id in [ScalarIntrinsic.floor,.fmuladd,.maxnum]! {if id==.maxnum {continue};if _:=reduced_floating_vector(id,ScalarVectorValue{},32,1) {assert false}}
 for bits in [u32(0),1,64]! {if _:=reduced_floating_vector(.minnum,ScalarVectorValue{},bits,1) {assert false}}
 for count in [0,17] {if _:=reduced_floating_vector(.maxnum,ScalarVectorValue{},32,count) {assert false}}
 for tag in [IntegerValue{aggregate:true},IntegerValue{vector:true}] {mut source:=ScalarVectorValue{};source.lanes[0]=tag;if _:=reduced_floating_vector(.minnum,source,32,1) {assert false}}
 println('AIR-NUMBER-REDUCTION-STATES: ${checks} all-lane poison/undef and mixed-state checks, name/shape/family/tag guards PASS')
}

fn test_number_reduction_nan_permutations() {
 mut checks:=0
 permutations:=[[0,1,2]!,[0,2,1]!,[1,0,2]!,[1,2,0]!,[2,0,1]!,[2,1,0]!]!
 for bits in [u32(16),32]! {
  sign:=u64(1)<<(bits-1);one:=if bits==16 {u64(0x3c00)} else {u64(0x3f800000)};snan:=if bits==16 {u64(0x7c01)} else {u64(0x7f800001)};qnan:=if bits==16 {u64(0x7e55)} else {u64(0x7fc12345)}
  for words3 in [[snan,u64(0),one]!,[qnan,u64(0),one]!,[snan,qnan,one]!,[snan,qnan,snan|sign]!,[qnan,u64(0),sign]!,[snan,sign,sign]!,[snan,one|sign,one]!,[qnan,one,qnan|sign]!] {
   for order in permutations {mut source:=ScalarVectorValue{};mut words:=[16]u64{};for lane in 0..3 {words[lane]=words3[order[lane]];source.lanes[lane]=IntegerValue{value:words[lane]}}
    for id in [ScalarIntrinsic.minnum,.maxnum]! {assert reduced_floating_vector(id,source,bits,3)! == IntegerValue{value:number_reduction_reference(id==.maxnum,bits,words,3)};checks++}
   }
  }
  for id in [ScalarIntrinsic.minnum,.maxnum]! {mut source:=ScalarVectorValue{};source.lanes[0]=IntegerValue{value:qnan};source.lanes[1]=IntegerValue{poison:true};assert reduced_floating_vector(id,source,bits,3)!.poison;checks++;source.undef=4;if _:=reduced_floating_vector(id,source,bits,3) {assert false};checks++}
 }
 assert checks==200
 println('AIR-NUMBER-REDUCTION-PERMUTATIONS: ${checks} directed signaling/quiet NaN, numeric extrema, signed zero and eager poison/undef checks PASS')
}
