// SPDX-License-Identifier: GPL-2.0-or-later
module airbitcode

fn clamp_number_reference(minimum bool, a u32, b u32) u32 {
	xnan := a & 0x7fffffff > 0x7f800000; ynan := b & 0x7fffffff > 0x7f800000
	if xnan && ynan { return 0x7fc00000 }; if xnan { return b }; if ynan { return a }
	if a & 0x7fffffff == 0 && b & 0x7fffffff == 0 { return a }
	xkey := if a >> 31 != 0 { ~a } else { a | u32(0x80000000) }
	ykey := if b >> 31 != 0 { ~b } else { b | u32(0x80000000) }
	return if (xkey < ykey) == minimum { a } else { b }
}

fn test_air_clamp_identity_domain_and_composition() {
	id, slot := air_float_intrinsic('air.clamp.f32')!
	assert id == .air_clamp && slot == 10 && scalar_air_float_cache_base + slot == 2178 && scalar_intrinsic_cache_slots == 2204
	assert scalar_intrinsic_name('air.clamp.f32')! == id && scalar_intrinsic_arity(id) == 3 && !scalar_integer_intrinsic(id)
	if _, _ := air_integer_intrinsic('air.clamp.f32') { assert false }
	for bits in [u32(0),64]! { if _ := scalar_air_float_clamp(bits,0,0,0) { assert false } }
	if _ := scalar_intrinsic_value(id,32,0,0) { assert false, 'ternary clamp through binary evaluator' }
	for name in ['air.clamp.f64','air.clamp.v2f32','air.clamp.i32','air.clamp.f032','air.clamp.f+32','air.clamp.f32.spoof','air.fast_clamp.f32','llvm.clamp.f32'] {
		if _ := scalar_intrinsic_name(name) { assert false, name }
	}
	edges := [u32(0),0x80000000,1,0x80000001,0x007fffff,0x00800000,0x3f000000,0x3f800000,0xbf800000,0x3f800001,0x3f7ffffe,0x40000000,0x7f7fffff,0xff7fffff,0x7f800000,0xff800000,0x7f800001,0xff800001,0x7fc12345,0xffc12345]!
	mut checks := 0; mut poisons := 0
	for sample in 0..131072 {
		x := if sample<8000 { edges[sample/400] } else { u32(sample)*u32(0x9e3779b9) }
		low := if sample<8000 { edges[(sample/20)%20] } else { u32(sample)*u32(0x85ebca6b)^u32(0xa5a5a5a5) }
		high := if sample<8000 { edges[sample%20] } else if sample%4==0 { low } else { u32(sample)*u32(0xc2b2ae35)^u32(0x5a5a5a5a) }
		lnan := low&0x7fffffff>0x7f800000; hnan := high&0x7fffffff>0x7f800000
		lkey := if low>>31!=0 { ~low } else { low|u32(0x80000000) }
		hkey := if high>>31!=0 { ~high } else { high|u32(0x80000000) }
		poison := !lnan&&!hnan&&!(low&0x7fffffff==0&&high&0x7fffffff==0)&&lkey>hkey
		result := scalar_air_float_clamp(32,u64(x)|u64(0x12345678)<<32,u64(low)|u64(0x87654321)<<32,u64(high)|u64(0xfedcba98)<<32)!
		assert result.poison == poison
		if poison { poisons++ } else { assert result.value == clamp_number_reference(true,clamp_number_reference(false,x,low),high) }
		checks++
	}
	for zero in [u64(0),0x80000000]! { for low in [u64(0),0x80000000]! { for high in [u64(0),0x80000000]! {
		r := scalar_air_float_clamp(32,zero,low,high)!; assert !r.poison && r.value==zero
	} } }
	assert checks==131072 && poisons>0
	println('AIR-CLAMP-UNIT: ${checks} independent ordered-key domain/composition checks (${poisons} poison), boundary triples, first-zero signs, normalization and exact identity/arity/width/name guards PASS')
}

fn half_clamp_reference_number(minimum bool, a u16, b u16) u16 {
 an := a & 0x7fff > 0x7c00; bn := b & 0x7fff > 0x7c00
 if an && bn { return 0x7e00 }; if an { return b }; if bn { return a }
 if a & 0x7fff == 0 && b & 0x7fff == 0 { return a }
 ak := if a >> 15 != 0 { ~a } else { a | u16(0x8000) }
 bk := if b >> 15 != 0 { ~b } else { b | u16(0x8000) }
 return if (ak < bk) == minimum { a } else { b }
}
fn test_air_half_clamp_identity_domain_all_encodings() {
 id,slot:=air_float_intrinsic('air.clamp.f16')!
 assert id==.air_clamp && scalar_air_float_cache_base+slot==2203 && scalar_intrinsic_cache_slots==2204
 assert scalar_intrinsic_name('air.clamp.f16')! == id && scalar_intrinsic_arity(id)==3 && !scalar_integer_intrinsic(id)
 edges:=[u16(0),0x8000,1,0x8001,0x03ff,0x0400,0x3800,0x3c00,0xbc00,0x3c01,0x3bfe,0x4000,0x7bff,0xfbff,0x7c00,0xfc00,0x7c01,0xfc01,0x7e45,0xfe45]!
 mut checks:=0;mut poisons:=0
 for sample in 0..204608 {
  mut x:=u16(0);mut low:=u16(0);mut high:=u16(0)
  if sample<8000 {x=edges[sample/400];low=edges[(sample/20)%20];high=edges[sample%20]}
  else {index:=sample-8000;raw:=u16(index%65536);a:=u16(u32(raw)*4051+17);b:=if index%4==0{a}else{u16(u32(raw)*7919+31)}
   match index/65536 {0{x=raw;low=a;high=b}1{x=a;low=raw;high=b}else{x=a;low=b;high=raw}}
  }
  ln:=low&0x7fff>0x7c00;hn:=high&0x7fff>0x7c00
  lk:=if low>>15!=0{~low}else{low|u16(0x8000)};hk:=if high>>15!=0{~high}else{high|u16(0x8000)}
  poison:=!ln&&!hn&&!(low&0x7fff==0&&high&0x7fff==0)&&lk>hk
  result:=scalar_air_float_clamp(16,u64(x)|~u64(0xffff),u64(low)|~u64(0xffff),u64(high)|~u64(0xffff))!
  assert result.poison==poison
  if poison{poisons++}else{assert result.value==half_clamp_reference_number(true,half_clamp_reference_number(false,x,low),high)}
  checks++
 }
 for x in [u64(0),0x8000]!{for low in [u64(0),0x8000]!{for high in [u64(0),0x8000]!{
  r:=scalar_air_float_clamp(16,x,low,high)!;assert !r.poison&&r.value==x
 }}}
 for name in ['air.clamp.f016','air.clamp.f+16','air.clamp.f16.spoof','air.clamp.v2f16','air.fast_clamp.f16','llvm.clamp.f16']{if _:=scalar_intrinsic_name(name){assert false}}
 for bits in [u32(0),1,64]!{if _:=scalar_air_float_clamp(bits,0,0,0){assert false}}
 if _:=scalar_intrinsic_value(.air_clamp,16,0,0){assert false}
 assert checks==204608&&poisons>0
 println('AIR-HALF-CLAMP: ${checks} independent ordered-key domain/composition checks (${poisons} poison), every half encoding in each operand position, 8000 boundary triples, zero ties, upper-bit masking, exact key/arity/name/width guards PASS')
}
