// SPDX-License-Identifier: GPL-2.0-or-later
module airbitcode

fn test_subinsert_lane_states_names_and_guards() {
 mut seen:=[8976]bool{};mut identities:=0;mut checks:=0
 for format in 0..66 {
  suffix:=if format<64 {'i${format+1}'}else if format==64 {'f16'}else{'f32'}
  for count in 1..17 {for source_count in 1..count+1 {
   name:='llvm.vector.insert.v${count}${suffix}.v${source_count}${suffix}'
   n,source,f:=vector_subinsert_name(name)!;assert n==count&&source==source_count&&f==format
   id,lanes,bits:=vector_float_intrinsic_name(name)!;assert id==.vector_insert&&lanes==count&&bits==if format<64 {u32(format+1)}else if format==64 {u32(16)}else{u32(32)}
   assert scalar_intrinsic_arity(id)==3;if _:=scalar_intrinsic_name(name) {assert false}
   key:=vector_subinsert_key(count,source_count,format)!;assert key>=52628&&key<61604&&!seen[key-52628];seen[key-52628]=true;identities++
   for offset in 0..count-source_count+1 {if offset%source_count!=0 {continue}
    for pattern in 0..32 {
     mut base:=ScalarVectorValue{};mut source_value:=ScalarVectorValue{}
     for lane in 0..count {
      base.lanes[lane]=IntegerValue{value:u64(0x9e3779b97f4a7c15)*u64(lane+pattern+1),poison:(lane+pattern)%5==0}
      source_value.lanes[lane]=IntegerValue{value:~base.lanes[lane].value,poison:(lane+pattern)%3==0}
      if (lane+pattern)%7==0 {base.undef|=u16(1)<<u32(lane)};if (lane+pattern)%4==0 {source_value.undef|=u16(1)<<u32(lane)}
     }
     original_base:=base;original_source:=source_value
     result:=inserted_subvector(base,source_value,count,source_count,offset)!;assert base==original_base&&source_value==original_source
     for lane in 0..count {
      inserted:=lane>=offset&&lane<offset+source_count;input:=if inserted {source_value}else{base};selected:=if inserted {lane-offset}else{lane}
      assert result.lanes[lane]==input.lanes[selected]&&(result.undef>>u32(lane))&1==(input.undef>>u32(selected))&1;checks++
     }
     for lane in count..16 {assert result.lanes[lane]==IntegerValue{}&&(result.undef>>u32(lane))&1==0}
    }
   }
  }}
 }
 assert identities==8976;for slot in seen {assert slot}
 for name in ['llvm.vector.insert.v0i8.v1i8','llvm.vector.insert.v01i8.v1i8','llvm.vector.insert.v17i8.v1i8','llvm.vector.insert.v1i8.v2i8','llvm.vector.insert.v2i8.v1i9','llvm.vector.insert.v2f16.v1i16','llvm.vector.insert.v2i0.v1i0','llvm.vector.insert.v2i65.v1i65','llvm.vector.insert.v2f64.v1f64','llvm.vector.insert.v2f016.v1f16','llvm.vector.insert.nxv2i8.v1i8','llvm.vector.insert.v2i8.nxv1i8','llvm.vector.insert.v2i8.v1i8.spoof','llvm.vector.insert.v2i8','llvm.vector.insert.v999999999999i8.v1i8'] {if _,_,_:=vector_subinsert_name(name) {assert false,name}}
 for shape in [[1,0,0]!,[1,2,0]!,[17,1,0]!,[2,1,-1]!,[4,2,1]!,[4,2,4]!] {if _:=inserted_subvector(ScalarVectorValue{},ScalarVectorValue{},shape[0],shape[1],shape[2]) {assert false}}
 for tag in [IntegerValue{aggregate:true},IntegerValue{vector:true}] {
  mut bad:=ScalarVectorValue{};bad.lanes[0]=tag
  if _:=inserted_subvector(bad,ScalarVectorValue{},2,1,1) {assert false};if _:=inserted_subvector(ScalarVectorValue{},bad,2,1,1) {assert false}
  assert inserted_subvector(bad,ScalarVectorValue{},2,1,0)!.lanes[0]==IntegerValue{}
 }
 println('AIR-SUBINSERT-UNIT: ${identities} overload/key identities, ${checks} raw lane/state copies, both source snapshots, overwritten-state removal and canonical shape/offset/tag guards PASS')
}
fn test_subinsert_immarg_slot_policy() {
 blocks:=[Block{parent:-1},Block{id:9,parent:0},Block{id:10,parent:0}]
 records:=[Record{block:1,code:2,values_count:1},Record{block:2,code:3,values_start:1,values_count:4}]
 mut values:=[u64(7),7,3,0,60];defer{unsafe{blocks.free();records.free();values.free()}}
 stream:=Stream{blocks:blocks,records:records,values:values};mut checks:=0
 for policy in [u64(0),2,3]! {for slot in [u64(0),1,2,3,4,0xffffffff]! {
  values[2]=slot
  if _:=intrinsic_declaration_attributes(stream,1,64,policy,.none) {assert policy!=0&&slot==policy}else{assert policy==0||slot!=policy};checks++
 }}
 values[2]=2;assert scalar_intrinsic_attributes_profile(stream,1,64,true)!>0
 values[2]=3;if _:=scalar_intrinsic_attributes_profile(stream,1,64,true) {assert false}
 for property in [u64(18),20,21,53,54]! {values[4]=property;if _:=intrinsic_declaration_attributes(stream,1,64,3,.none) {assert false};checks++}
 values[4]=60;if _:=intrinsic_declaration_attributes(stream,1,1,3,.none) {assert false};checks++
 println('AIR-SUBINSERT-ATTRIBUTES: ${checks+2} exact no/second/third-parameter immarg policy, property and budget checks PASS')
}
