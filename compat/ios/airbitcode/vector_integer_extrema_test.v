// SPDX-License-Identifier: GPL-2.0-or-later
module airbitcode

// Reconstruct signed values without a signed overflow or unsigned sign-key flip.
fn vector_extrema_signed(width u32,value u64) i64 {
 x:=value&constant_mask(width);return if x&(u64(1)<<(width-1))!=0 {-i64((~x)&constant_mask(width))-1}else{i64(x)}
}
fn vector_extrema_reference(id ScalarIntrinsic,width u32,a u64,b u64) u64 {
 x:=a&constant_mask(width);y:=b&constant_mask(width)
 less:=if id in [.smin,.smax]!{vector_extrema_signed(width,x)<vector_extrema_signed(width,y)}else{x<y}
 return if (id in [.smin,.umin]! && less)||(id in [.smax,.umax]! && !less){x}else{y}
}
fn vector_extrema_word(width u32,k int) u64 {
 mask:=constant_mask(width);sign:=u64(1)<<(width-1)
 return (match k%12 {0{u64(0)} 1{mask} 2{sign} 3{sign-1} 4{sign+1} 5{mask-1} 6{u64(1)} 7{u64(0x5555555555555555)} 8{u64(0xaaaaaaaaaaaaaaaa)} 9{u64(1)<<u32(k%int(width))} 10{mask^(u64(1)<<u32(k%int(width)))} else{u64(k)*u64(0x9e3779b97f4a7c15)}})&mask
}
fn test_vector_integer_extrema_values_and_snapshots() {
 mut checks:=0
 for id in [ScalarIntrinsic.smin,.smax,.umin,.umax]!{for width in u32(1)..65{for count in 1..17{for sample in 0..int(width*2+16){
  mask:=constant_mask(width);mut a:=ScalarVectorValue{};mut b:=a
  for lane in 0..count{k:=sample+lane;x:=vector_extrema_word(width,k);y:=if k%5==0{x}else if k%5==1{x^1}else{vector_extrema_word(width,k+5)};a.lanes[lane]=IntegerValue{value:x|~mask};b.lanes[lane]=IntegerValue{value:y|~mask}}
  olda:=a;oldb:=b;result:=integer_extremum_vector(id,a,b,width,count)!;reverse:=integer_extremum_vector(id,b,a,width,count)!;same:=integer_extremum_vector(id,a,a,width,count)!
  for lane in 0..count{assert result.lanes[lane]==IntegerValue{value:vector_extrema_reference(id,width,a.lanes[lane].value,b.lanes[lane].value)};assert reverse.lanes[lane]==result.lanes[lane];assert same.lanes[lane]==IntegerValue{value:a.lanes[lane].value&mask};checks++};assert a==olda&&b==oldb&&result.undef==0
 }}}};assert checks==2820096
 println('AIR-VECTOR-INTEGER-EXTREMA-VALUES: ${checks} independent signed/unsigned comparisons, symmetry/idempotence, i1/i64 boundaries, all widths/counts, padding and snapshots PASS')
}
fn test_vector_integer_extrema_exhaustion_and_patterns() {
 mut checks:=0
 for id in [ScalarIntrinsic.smin,.smax,.umin,.umax]!{for width in u32(1)..65{mask:=constant_mask(width);samples:=if width<=8{int(u64(1)<<(width*2))}else{4096}
  for chunk in 0..(samples+15)/16{mut a:=ScalarVectorValue{};mut b:=a;for lane in 0..16{k:=u64((chunk*16+lane)%samples);x:=if width<=8{k&mask}else{k*u64(0x9e3779b97f4a7c15)};y:=if width<=8{k>>width}else{(k*u64(0xd1b54a32d192ed03))^(k<<47)};a.lanes[lane]=IntegerValue{value:x|~mask};b.lanes[lane]=IntegerValue{value:y|~mask}}
   result:=integer_extremum_vector(id,a,b,width,16)!;for lane in 0..16{assert result.lanes[lane]==IntegerValue{value:vector_extrema_reference(id,width,a.lanes[lane].value,b.lanes[lane].value)};checks++}
  }
 }};assert checks==1267072
 println('AIR-VECTOR-INTEGER-EXTREMA-SWEEP: ${checks} comparisons, every i1-i8 pair and 4096 patterned pairs per wider width/operation PASS')
}
fn test_vector_integer_extrema_states_names_and_guards() {
 mut checks:=0;mut seen:=[4096]bool{}
 for id in [ScalarIntrinsic.smin,.smax,.umin,.umax]!{for width in u32(1)..65{for count in 1..17{
  parsed,n,w:=vector_float_intrinsic_name('llvm.${id}.v${count}i${width}')!;assert parsed==id&&n==count&&w==width;key:=vector_float_intrinsic_key(id,count,width)!;assert key>=6848&&key<10944&&!seen[key-6848];seen[key-6848]=true
  for source in 0..2{for target in 0..count{mut a:=ScalarVectorValue{};mut b:=a;if source==0{a.lanes[target]=IntegerValue{poison:true}}else{b.lanes[target]=IntegerValue{poison:true}};result:=integer_extremum_vector(id,a,b,width,count)!;for lane in 0..count{assert result.lanes[lane].poison==(lane==target);checks++};assert frozen_vector(result,count)!.lanes[target]==IntegerValue{}
   if source==0{a.undef=u16(1)<<u32(target)}else{b.undef=u16(1)<<u32(target)};if _:=integer_extremum_vector(id,a,b,width,count){assert false,'strict undef'};checks++
  }}
 }}};for slot in seen{assert slot};assert checks==835584
 for prefix in ['smin','smax','umin','umax']{for suffix in ['i32','v0i32','v01i32','v17i32','v999999999i32','v2i0','v2i01','v2i65','v2i128','v2i+1','v2i1x','v2i32.i32','v2f32','nxv2i32']{name:='llvm.${prefix}.${suffix}';if _,_,_:=vector_float_intrinsic_name(name){assert false,name}}}
 for id in [ScalarIntrinsic.fshl,.ctlz,.minimum]!{if _:=integer_extremum_vector(id,ScalarVectorValue{},ScalarVectorValue{},32,1){assert false,'family'}}
 for width in [u32(0),65,128]!{if _:=integer_extremum_vector(.smin,ScalarVectorValue{},ScalarVectorValue{},width,1){assert false,'width'}}
 for count in [0,17]{if _:=integer_extremum_vector(.umax,ScalarVectorValue{},ScalarVectorValue{},32,count){assert false,'count'}}
 for source in 0..2{for tag in [IntegerValue{aggregate:true},IntegerValue{vector:true}]{mut a:=ScalarVectorValue{};mut b:=a;if source==0{a.lanes[0]=tag}else{b.lanes[0]=tag};if _:=integer_extremum_vector(.smax,a,b,32,1){assert false,'lane tag'}}}
 println('AIR-VECTOR-INTEGER-EXTREMA-STATES: ${checks} poison/undef/freeze checks, all 4096 cache identities and family/shape/name/tag guards PASS')
}
