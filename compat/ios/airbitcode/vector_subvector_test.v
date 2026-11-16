// SPDX-License-Identifier: GPL-2.0-or-later
module airbitcode

fn test_subvector_names_state_and_guards() {
 mut seen := [8976]bool{}; mut identities := 0; mut checks := 0
 for format in 0 .. 66 {
  suffix := if format < 64 {'i${format+1}'}else if format==64 {'f16'}else{'f32'}
  for source_count in 1 .. 17 { for count in 1 .. source_count + 1 {
   name := 'llvm.vector.extract.v${count}${suffix}.v${source_count}${suffix}'
   n,source,f := vector_subvector_name(name)!;assert n==count&&source==source_count&&f==format
   id,lanes,bits := vector_float_intrinsic_name(name)!;assert id==.vector_extract&&lanes==count&&bits==if format<64 {u32(format+1)}else if format==64 {u32(16)}else{u32(32)}
   assert scalar_intrinsic_arity(id)==2;if _:=scalar_intrinsic_name(name) {assert false}
   key:=vector_subvector_key(count,source_count,format)!;assert key>=43652&&key<52628&&!seen[key-43652];seen[key-43652]=true;identities++
   for offset in 0 .. source_count-count+1 {if offset%count!=0 {continue}
    for pattern in 0 .. 32 {
     mut source_value:=ScalarVectorValue{}
     for lane in 0 .. source_count {
      source_value.lanes[lane]=IntegerValue{value:u64(0x9e3779b97f4a7c15)*u64(lane+pattern+1),poison:(lane+pattern)%5==0}
      if (lane+pattern)%7==0 {source_value.undef|=u16(1)<<u32(lane)}
     }
     original:=source_value;result:=extracted_subvector(source_value,count,source_count,offset)!;assert source_value==original
     for lane in 0 .. count {assert result.lanes[lane]==source_value.lanes[offset+lane];assert (result.undef>>u32(lane))&1==(source_value.undef>>u32(offset+lane))&1;checks++}
     for lane in count .. 16 {assert result.lanes[lane]==IntegerValue{}&&(result.undef>>u32(lane))&1==0}
    }
   }
  }}
 }
 assert identities==8976;for slot in seen {assert slot}
 for name in ['llvm.vector.extract.v0i8.v1i8','llvm.vector.extract.v01i8.v1i8','llvm.vector.extract.v17i8.v17i8','llvm.vector.extract.v2i8.v1i8','llvm.vector.extract.v1i8.v2i9','llvm.vector.extract.v1f16.v2i16','llvm.vector.extract.v1i0.v2i0','llvm.vector.extract.v1i65.v2i65','llvm.vector.extract.v1f64.v2f64','llvm.vector.extract.v1f016.v2f16','llvm.vector.extract.nxv1i8.v2i8','llvm.vector.extract.v1i8.nxv2i8','llvm.vector.extract.v1i8.v2i8.spoof','llvm.vector.extract.v1i8','llvm.vector.extract.v999999999999i8.v2i8'] {if _,_,_:=vector_subvector_name(name) {assert false,name}}
 for shape in [[0,1,0]!,[2,1,0]!,[1,17,0]!,[1,2,-1]!,[2,4,1]!,[2,4,4]!] {if _:=extracted_subvector(ScalarVectorValue{},shape[0],shape[1],shape[2]) {assert false}}
 for tag in [IntegerValue{aggregate:true},IntegerValue{vector:true}] {mut source:=ScalarVectorValue{};source.lanes[1]=tag;if _:=extracted_subvector(source,1,2,1) {assert false};assert extracted_subvector(source,1,2,0)!.lanes[0]==IntegerValue{}}
 println('AIR-SUBVECTOR-UNIT: ${identities} overload/key identities, ${checks} raw lane/state copies, snapshots/unused lanes and canonical shape/offset/tag guards PASS')
}
