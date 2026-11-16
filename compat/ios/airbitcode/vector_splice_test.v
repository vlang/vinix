// SPDX-License-Identifier: GPL-2.0-or-later
module airbitcode

fn test_vector_splice_raw_lanes_and_states() {
 mut checks:=0
 for count in 1..17 {for sample in u64(0)..1024 {
  mut a:=ScalarVectorValue{};mut b:=ScalarVectorValue{}
  for lane in 0..count {
   a.lanes[lane]=IntegerValue{value:sample*u64(0x9e3779b97f4a7c15)+u64(lane),poison:(int(sample)+lane)%7==0}
   b.lanes[lane]=IntegerValue{value:~a.lanes[lane].value,poison:(int(sample)+lane)%5==0}
   if (int(sample)+lane)%11==0 {a.undef|=u16(1)<<u32(lane)}
   if (int(sample)+lane)%13==0 {b.undef|=u16(1)<<u32(lane)}
  }
  before_a:=a;before_b:=b
  for amount in 0..count+2 {for id in [ScalarIntrinsic.vector_splice_left,.vector_splice_right]! {
   result:=spliced_vector(id,a,b,count,IntegerValue{value:u64(amount)})!
   mirror:=spliced_vector(if id==.vector_splice_left {ScalarIntrinsic.vector_splice_right}else{ScalarIntrinsic.vector_splice_left},a,b,count,IntegerValue{value:if amount<=count {u64(count-amount)}else{u64(amount)}})!
   assert result==mirror
   for lane in 0..count {
    if amount>count {assert result.lanes[lane].poison&&result.undef==0}else{
     start:=if id==.vector_splice_left {amount}else{count-amount};selected:=start+lane;src:=if selected<count {a}else{b};index:=selected%count
     assert result.lanes[lane]==src.lanes[index]
     assert (result.undef>>u32(lane))&1==(src.undef>>u32(index))&1
    };checks++
   }
   assert a==before_a&&b==before_b
  }}
  for offset in [IntegerValue{poison:true},IntegerValue{value:0xffffffff}] {
   result:=spliced_vector(.vector_splice_left,a,b,count,offset)!;for lane in 0..count {assert result.lanes[lane].poison};assert result.undef==0
  }
 }}
 assert checks==3620864
 println('AIR-VECTOR-SPLICE-VALUES: ${checks} raw lane/state comparisons, all offsets and counts, mirrored directions, poison offsets and source snapshots PASS')
}
fn test_vector_splice_names_keys_guards() {
 mut seen:=[2112]bool{}
 for id in [ScalarIntrinsic.vector_splice_left,.vector_splice_right]! {for format in 0..66 {for count in 1..17 {
  suffix:=if format<64 {'i${format+1}'}else if format==64 {'f16'}else{'f32'}
  name:='llvm.vector.splice.${if id==.vector_splice_left {'left'}else{'right'}}.v${count}${suffix}'
  actual,n,f:=vector_splice_name(name)!;assert actual==id&&n==count&&f==format
  parsed,lanes,width:=vector_float_intrinsic_name(name)!;assert parsed==id&&lanes==count&&width==if format<64 {u32(format+1)}else if format==64 {u32(16)}else{u32(32)}
  key:=vector_splice_key(id,count,format)!;assert key>=37888&&key<40000&&!seen[key-37888];seen[key-37888]=true;assert scalar_intrinsic_arity(id)==3
 }}}
 for value in seen {assert value}
 for name in ['llvm.vector.splice.left.v0i32','llvm.vector.splice.right.v17i32','llvm.vector.splice.left.v01i32','llvm.vector.splice.right.v2i0','llvm.vector.splice.left.v2i65','llvm.vector.splice.right.v2f64','llvm.vector.splice.left.nxv2i32','llvm.vector.splice.right.v2bf16','llvm.vector.splice.left.v2i32.spoof','llvm.vector.splice.left.i32','llvm.vector.splice.v2i32','llvm.vector.splice.left.v99999999999999999999i32'] {if _,_,_:=vector_splice_name(name) {assert false,name}}
 for count in [0,17] {if _:=spliced_vector(.vector_splice_left,ScalarVectorValue{},ScalarVectorValue{},count,IntegerValue{}) {assert false}}
 for format in [-1,66] {if _:=vector_splice_key(.vector_splice_left,1,format) {assert false}}
 if _:=vector_splice_key(.vector_reverse,1,0) {assert false}
 for tag in [IntegerValue{aggregate:true},IntegerValue{vector:true}] {
  mut source:=ScalarVectorValue{};source.lanes[0]=tag
  if _:=spliced_vector(.vector_splice_left,source,ScalarVectorValue{},1,IntegerValue{}) {assert false}
  if _:=spliced_vector(.vector_splice_right,ScalarVectorValue{},source,1,IntegerValue{}) {assert false}
  if _:=spliced_vector(.vector_splice_left,ScalarVectorValue{},ScalarVectorValue{},1,tag) {assert false}
 }
 println('AIR-VECTOR-SPLICE-NAMES: 2112 integer/half/float identities and canonical name/family/count/tag guards PASS')
}
