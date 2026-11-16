// SPDX-License-Identifier: GPL-2.0-or-later
module airbitcode

// AIR and LLVM calls share evaluators, but keep distinct declaration identities.
const vector_air_unary_cache_base = vector_subinsert_cache_base + 8976

fn air_vector_unary_index(id ScalarIntrinsic) !int {
	return match id { .fabs { 0 } .floor { 1 } .ceil { 2 } .trunc { 3 } .sqrt { 4 } .round { 5 } .rint { 6 } else { return error('AIR vector unary: unsupported family') } }
}

fn air_vector_unary_name(name string) !(ScalarIntrinsic, int, u32) {
	mut id := ScalarIntrinsic.fabs
	mut offset := 10
	if name.starts_with('air.fabs.v') {}
	else if name.starts_with('air.floor.v') { id = .floor; offset = 11 }
	else if name.starts_with('air.ceil.v') { id = .ceil }
	else if name.starts_with('air.trunc.v') { id = .trunc; offset = 11 }
	else if name.starts_with('air.sqrt.v') { id = .sqrt }
	else if name.starts_with('air.round.v') { id = .round; offset = 11 }
	else if name.starts_with('air.rint.v') { id = .rint }
	else { return error('AIR vector unary: unsupported name') }
	count, bits := vector_float_overload(name, offset)!
	if bits != 32 { return error('AIR vector unary: float32 required') }
	return id, count, bits
}

fn air_vector_unary_key(id ScalarIntrinsic, count int, bits u32) !int {
	if count < 1 || count > 16 || bits != 32 { return error('AIR vector unary: cache shape') }
	return vector_air_unary_cache_base + air_vector_unary_index(id)! * 16 + count - 1
}
