// SPDX-License-Identifier: GPL-2.0-or-later
module airbitcode

fn test_vector_reverse_all_encodings_and_states() {
	mut checks := 0
	for count in 1 .. 17 { for sample in u64(0) .. 65536 {
		mut source := ScalarVectorValue{}
		for lane in 0 .. count { source.lanes[lane] = IntegerValue{value: sample * u64(0x9e3779b97f4a7c15) + u64(lane), poison: (int(sample) + lane) % 7 == 0}; if (int(sample) + lane) % 11 == 0 { source.undef |= u16(1) << u32(lane) } }
		before := source; result := reversed_vector(source, count)!
		for lane in 0 .. count { selected:=count-1-lane;assert result.lanes[lane] == source.lanes[selected];assert (result.undef >> u32(lane)) & 1 == (source.undef >> u32(selected)) & 1;checks++ }
		assert reversed_vector(result, count)! == before && source == before
	} }
	assert checks == 8912896
	println('AIR-VECTOR-REVERSE-VALUES: ${checks} raw lane/poison/undef comparisons, all counts 1-16, double-reverse identity and source snapshots PASS')
}
fn test_vector_reverse_overloads_cache_and_guards() {
	mut seen := [1056]bool{}
	for format in 0 .. 66 { for count in 1 .. 17 {
		suffix := if format < 64 { 'i${format + 1}' } else if format == 64 { 'f16' } else { 'f32' }
		name := 'llvm.vector.reverse.v${count}${suffix}'; n, f := vector_reverse_name(name)!; assert n==count&&f==format
		id, lanes, bits := vector_float_intrinsic_name(name)!; assert id == .vector_reverse && lanes==count && bits==if format<64 {u32(format+1)}else if format==64 {u32(16)}else{u32(32)}
		key:=vector_reverse_key(n,f)!;assert key==36832+format*16+count-1&&!seen[key-36832];seen[key-36832]=true
		assert scalar_intrinsic_arity(id)==1
	} }
	for value in seen {assert value}
	for name in ['llvm.vector.reverse.v0i32','llvm.vector.reverse.v17i32','llvm.vector.reverse.v01i32','llvm.vector.reverse.v2i0','llvm.vector.reverse.v2i65','llvm.vector.reverse.v2f64','llvm.vector.reverse.nxv2i32','llvm.vector.reverse.v2bf16','llvm.vector.reverse.v2i32.spoof','llvm.vector.reverse.i32','llvm.experimental.vector.reverse.v2i32','llvm.vector.reverse.v99999999999999999999i32'] {if _,_:=vector_reverse_name(name) {assert false,name}}
	if _:=scalar_intrinsic_name('llvm.vector.reverse.v2i32') {assert false,'scalar path'}
	for count in [0,17] {if _:=reversed_vector(ScalarVectorValue{},count) {assert false};if _:=vector_reverse_key(count,0) {assert false}}
	for format in [-1,66] {if _:=vector_reverse_key(1,format) {assert false}}
	for tag in [IntegerValue{aggregate:true},IntegerValue{vector:true}] {mut source:=ScalarVectorValue{};source.lanes[0]=tag;if _:=reversed_vector(source,1) {assert false}}
	println('AIR-VECTOR-REVERSE-NAMES: 1056 distinct integer/half/float identities, canonical overloads and family/count/tag guards PASS')
}
