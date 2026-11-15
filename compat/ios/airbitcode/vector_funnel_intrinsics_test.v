// SPDX-License-Identifier: GPL-2.0-or-later
module airbitcode

// Select each output bit from a conceptual 2W-bit concatenation. No wide shifts.
fn vector_funnel_reference(id ScalarIntrinsic, width u32, a u64, b u64, amount u64) u64 {
 shift := int((amount & constant_mask(width)) % u64(width)); mut result := u64(0)
 for bit in 0 .. int(width) {
  pos := if id == .fshl { int(width) + bit - shift } else { bit + shift }
  source := if pos >= int(width) { a } else { b }
  index := if pos >= int(width) { pos - int(width) } else { pos }
  result |= ((source >> u32(index)) & 1) << u32(bit)
 }
 return result
}
fn test_vector_funnel_values_and_snapshots() {
 mut checks := 0
 for id in [ScalarIntrinsic.fshl, .fshr]! { for width in u32(1) .. 65 {for count in 1 .. 17 {for sample in 0 .. int(width * 2 + 16) {
  mask := constant_mask(width); mut a := ScalarVectorValue{}; mut b := ScalarVectorValue{}; mut c := ScalarVectorValue{}
  for lane in 0 .. count {
   k := sample + lane; x := if k % 5 == 0 { u64(0) } else if k % 5 == 1 { mask } else { u64(1) << u32(k % int(width)) }
   y := if k % 7 == 0 { u64(0) } else if k % 7 == 1 { mask } else { u64(k) * u64(0x9e3779b97f4a7c15) }
   z := if k % 9 == 0 { u64(0) } else if k % 9 == 1 { u64(width) } else if k % 9 == 2 { u64(width + 1) } else if k % 9 == 3 { mask } else { u64(k) }
   a.lanes[lane] = IntegerValue{value: x | ~mask}; b.lanes[lane] = IntegerValue{value: y | ~mask}; c.lanes[lane] = IntegerValue{value: z | ~mask}
  }
  olda := a; oldb := b; oldc := c; result := funnel_intrinsic_vector(id,a,b,c,width,count)!
  for lane in 0 .. count { assert result.lanes[lane] == IntegerValue{value:vector_funnel_reference(id,width,a.lanes[lane].value,b.lanes[lane].value,c.lanes[lane].value)};checks++ }
  assert a==olda && b==oldb && c==oldc && result.undef==0
 }}}};assert checks==1410048
 println('AIR-VECTOR-FUNNEL-VALUES: ${checks} independent bit-selection comparisons, both directions, all widths/counts, modulo/zero shifts, noisy padding and snapshots PASS')
}
fn test_vector_funnel_exhaustion_and_wide_patterns() {
 mut checks:=0
 for id in [ScalarIntrinsic.fshl,.fshr]! {for width in u32(1)..65 {
  samples:=if width<=5 {int(u64(1)<<(width*3))}else{4096};mask:=constant_mask(width)
  for chunk in 0..(samples+15)/16 {mut a:=ScalarVectorValue{};mut b:=ScalarVectorValue{};mut c:=ScalarVectorValue{}
   for lane in 0..16 {k:=u64((chunk*16+lane)%samples);x:=if width<=5{k&mask}else{k*u64(0x9e3779b97f4a7c15)};y:=if width<=5{(k>>width)&mask}else{(k*u64(0xd1b54a32d192ed03))^(k<<47)};z:=if width<=5{k>>(width*2)}else{k^(k>>3)};a.lanes[lane]=IntegerValue{value:x|~mask};b.lanes[lane]=IntegerValue{value:y|~mask};c.lanes[lane]=IntegerValue{value:z|~mask}}
   result:=funnel_intrinsic_vector(id,a,b,c,width,16)!
   for lane in 0..16 {assert result.lanes[lane]==IntegerValue{value:vector_funnel_reference(id,width,a.lanes[lane].value,b.lanes[lane].value,c.lanes[lane].value)};checks++}
  }
 }};assert checks==558240
 println('AIR-VECTOR-FUNNEL-SWEEP: ${checks} comparisons, every i1-i5 triple and 4096 patterns per wider width/direction PASS')
}
fn test_vector_funnel_states_names_and_guards() {
 mut seen:=[2048]bool{};mut checks:=0
 for id in [ScalarIntrinsic.fshl,.fshr]! {for width in u32(1)..65 {for count in 1..17 {
  parsed,n,w:=vector_float_intrinsic_name('llvm.${id}.v${count}i${width}')!;assert parsed==id&&n==count&&w==width;key:=vector_float_intrinsic_key(id,count,width)!;assert key>=4800&&key<6848&&!seen[key-4800];seen[key-4800]=true
  for source in 0..3 {for target in 0..count {
   mut a:=ScalarVectorValue{};mut b:=a;mut c:=a;poison:=IntegerValue{poison:true}
   if source==0 {a.lanes[target]=poison}else if source==1{b.lanes[target]=poison}else{c.lanes[target]=poison}
   result:=funnel_intrinsic_vector(id,a,b,c,width,count)!;for lane in 0..count{assert result.lanes[lane].poison==(lane==target);checks++};assert frozen_vector(result,count)!.lanes[target]==IntegerValue{}
   if source==0{a.undef=u16(1)<<u32(target)}else if source==1{b.undef=u16(1)<<u32(target)}else{c.undef=u16(1)<<u32(target)}
   if _:=funnel_intrinsic_vector(id,a,b,c,width,count){assert false,'strict undef in every source'};checks++
  }}
 }}};for value in seen{assert value};assert checks==626688
 for prefix in ['fshl','fshr'] {for suffix in ['i32','v0i32','v01i32','v17i32','v999999999i32','v2i0','v2i01','v2i65','v2i128','v2i+1','v2i1x','v2i32.i32','v2f32','nxv2i32']{name:='llvm.${prefix}.${suffix}';if _,_,_:=vector_float_intrinsic_name(name){assert false,name}}}
 for id in [ScalarIntrinsic.ctpop,.ctlz,.fabs]!{if _:=funnel_intrinsic_vector(id,ScalarVectorValue{},ScalarVectorValue{},ScalarVectorValue{},32,1){assert false,'family'}}
 for width in [u32(0),65,128]!{if _:=funnel_intrinsic_vector(.fshl,ScalarVectorValue{},ScalarVectorValue{},ScalarVectorValue{},width,1){assert false,'width'}}
 for count in [0,17]{if _:=funnel_intrinsic_vector(.fshr,ScalarVectorValue{},ScalarVectorValue{},ScalarVectorValue{},32,count){assert false,'count'}}
 for source in 0..3{for tag in [IntegerValue{aggregate:true},IntegerValue{vector:true}]{mut a:=ScalarVectorValue{};mut b:=a;mut c:=a;if source==0{a.lanes[0]=tag}else if source==1{b.lanes[0]=tag}else{c.lanes[0]=tag};if _:=funnel_intrinsic_vector(.fshl,a,b,c,32,1){assert false,'lane tag'}}}
 println('AIR-VECTOR-FUNNEL-STATES: ${checks} poison/undef/freeze checks across all three sources; 2048 names/cache identities and guards PASS')
}
