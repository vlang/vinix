// SPDX-License-Identifier: GPL-2.0-or-later
module airbitcode

fn test_sequential_reduction_identity_encodings() {
 mut checks:=0
 for bits in [u32(16),32]! {for sample in 0..65536 {
  word:=if bits==16 {u64(sample)} else {u64(u32(sample)*u32(0x9e3779b9))}
  sign:=u64(1)<<(bits-1);infinity:=if bits==16 {u64(0x7c00)} else {u64(0x7f800000)}
  expected:=if word&(sign-1)>infinity {if bits==16 {u64(0x7e00)} else {u64(0x7fc00000)}} else {word}
  mut source:=ScalarVectorValue{};source.lanes[0]=IntegerValue{value:word|~constant_mask(bits)};before:=source
  for id in [FloatingSequentialReduction.sum,.product]! {
   seed:=if id==.sum {sign} else if bits==16 {u64(0x3c00)} else {u64(0x3f800000)}
   assert reduced_sequential_vector(id,IntegerValue{value:seed|~constant_mask(bits)},source,bits,1)! == IntegerValue{value:expected}
   assert source==before;checks++
  }
 }}
 assert checks==262144
 println('AIR-SEQUENTIAL-REDUCTION-IDENTITIES: ${checks} all-half/deterministic-float identities, NaNs, signed zeros, upper-bit masks and snapshots PASS')
}
fn test_sequential_reduction_order_and_exact_values(){
 mut checks:=0
 for bits in [u32(16),32]! {
  one:=if bits==16 {u64(0x3c00)} else {u64(0x3f800000)};two:=if bits==16 {u64(0x4000)} else {u64(0x40000000)};half:=if bits==16 {u64(0x3800)} else {u64(0x3f000000)};sign:=u64(1)<<(bits-1);large:=if bits==16 {u64(0x6800)} else {u64(0x4b800000)};largest:=if bits==16 {u64(0x7bff)} else {u64(0x7f7fffff)};inf:=if bits==16 {u64(0x7c00)} else {u64(0x7f800000)}
  for count in 1..17 {
   mut source:=ScalarVectorValue{}
   for lane in 0..count {source.lanes[lane]=IntegerValue{value:one|if lane%2==0 {u64(0)} else {sign}}}
   assert reduced_sequential_vector(.sum,IntegerValue{value:one},source,bits,count)!.value==if count%2==0 {one} else {two};checks++
   for lane in 0..count {source.lanes[lane]=IntegerValue{value:one|sign}}
   assert reduced_sequential_vector(.product,IntegerValue{value:one},source,bits,count)!.value==one|if count%2==0 {u64(0)} else {sign};checks++
   for lane in 0..count {source.lanes[lane]=IntegerValue{value:sign}}
   assert reduced_sequential_vector(.sum,IntegerValue{value:sign},source,bits,count)!.value==sign;checks++
   assert reduced_sequential_vector(.sum,IntegerValue{},source,bits,count)!.value==0;checks++
  }
  for reverse in [false,true] {
   mut source:=ScalarVectorValue{};source.lanes[0]=IntegerValue{value:if reverse {large|sign} else {one}};source.lanes[1]=IntegerValue{value:if reverse {one} else {large|sign}}
   assert reduced_sequential_vector(.sum,IntegerValue{value:large},source,bits,2)!.value==if reverse {one} else {u64(0)};checks++
   source.lanes[0]=IntegerValue{value:if reverse {two} else {half}};source.lanes[1]=IntegerValue{value:if reverse {half} else {two}}
   assert reduced_sequential_vector(.product,IntegerValue{value:1},source,bits,2)!.value==if reverse {u64(1)} else {u64(0)};checks++
   source.lanes[0]=IntegerValue{value:if reverse {half} else {two}};source.lanes[1]=IntegerValue{value:if reverse {two} else {half}}
   assert reduced_sequential_vector(.product,IntegerValue{value:largest},source,bits,2)!.value==if reverse {largest} else {inf};checks++
  }
 }
 assert checks==140
 println('AIR-SEQUENTIAL-REDUCTION-ORDER: ${checks} exact values, signed zeros and directed cancellation/underflow/overflow order checks PASS')
}
fn test_sequential_reduction_states_and_names(){
 mut checks:=0
 for bits in [u32(16),32]! {for id in [FloatingSequentialReduction.sum,.product]! {for count in 1..17 {
  assert reduced_sequential_vector(id,IntegerValue{poison:true},ScalarVectorValue{},bits,count)!.poison;checks++
  for lane in 0..count {mut source:=ScalarVectorValue{};source.lanes[lane]=IntegerValue{poison:true};assert reduced_sequential_vector(id,IntegerValue{},source,bits,count)!.poison;checks++;source.undef=u16(1)<<u32(lane);if _:=reduced_sequential_vector(id,IntegerValue{poison:true},source,bits,count) {assert false};checks++}
 }}}
 assert checks==1152
 for name in ['llvm.vector.reduce.fadd.v0f16','llvm.vector.reduce.fmul.v01f32','llvm.vector.reduce.fadd.v17f32','llvm.vector.reduce.fmul.v2f64','llvm.vector.reduce.fadd.v2i32','llvm.vector.reduce.fadd.nxv2f32','llvm.vector.reduce.fmul.v2f32.spoof','llvm.vector.reduce.fadd.v2f016'] {if _,_,_:=sequential_vector_reduction_name(name) {assert false,name}}
 for bits in [u32(0),1,64]! {if _:=reduced_sequential_vector(.sum,IntegerValue{},ScalarVectorValue{},bits,1) {assert false}}
 for count in [0,17] {if _:=reduced_sequential_vector(.product,IntegerValue{},ScalarVectorValue{},32,count) {assert false}}
 for tag in [IntegerValue{aggregate:true},IntegerValue{vector:true}] {if _:=reduced_sequential_vector(.sum,tag,ScalarVectorValue{},32,1) {assert false};mut source:=ScalarVectorValue{};source.lanes[0]=tag;if _:=reduced_sequential_vector(.sum,IntegerValue{},source,32,1) {assert false}}
 println('AIR-SEQUENTIAL-REDUCTION-STATES: ${checks} seed/lane poison and eager undef checks, name/shape/tag guards PASS')
}
