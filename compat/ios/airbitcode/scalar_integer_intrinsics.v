// SPDX-License-Identifier: GPL-2.0-or-later
module airbitcode

fn scalar_integer_intrinsic(id ScalarIntrinsic) bool {
	return id in [.ctpop, .bitreverse, .bswap, .ctlz, .cttz, .fshl, .fshr, .smin, .smax, .umin, .umax, .iabs, .sadd_sat, .uadd_sat, .ssub_sat, .usub_sat, .sshl_sat, .ushl_sat]!
}
fn scalar_integer_saturating_shift(id ScalarIntrinsic) bool { return id in [.sshl_sat, .ushl_sat]! }
fn scalar_integer_saturating(id ScalarIntrinsic) bool { return id in [.sadd_sat, .uadd_sat, .ssub_sat, .usub_sat]! }
fn scalar_integer_poison_flag(id ScalarIntrinsic) bool { return scalar_integer_zero_count(id) || id == .iabs }
fn scalar_integer_extremum(id ScalarIntrinsic) bool { return id in [.smin, .smax, .umin, .umax]! }
fn scalar_integer_funnel(id ScalarIntrinsic) bool { return id in [.fshl, .fshr]! }
fn scalar_integer_zero_count(id ScalarIntrinsic) bool { return id in [.ctlz, .cttz]! }
fn scalar_integer_intrinsic_name(name string) !ScalarIntrinsic {
	id := if name.starts_with('llvm.ctpop.i') { ScalarIntrinsic.ctpop }
		else if name.starts_with('llvm.bitreverse.i') { ScalarIntrinsic.bitreverse }
		else if name.starts_with('llvm.bswap.i') { ScalarIntrinsic.bswap }
		else if name.starts_with('llvm.ctlz.i') { ScalarIntrinsic.ctlz }
		else if name.starts_with('llvm.cttz.i') { ScalarIntrinsic.cttz }
		else if name.starts_with('llvm.fshl.i') { ScalarIntrinsic.fshl }
		else if name.starts_with('llvm.fshr.i') { ScalarIntrinsic.fshr }
		else if name.starts_with('llvm.smin.i') { ScalarIntrinsic.smin }
		else if name.starts_with('llvm.smax.i') { ScalarIntrinsic.smax }
		else if name.starts_with('llvm.umin.i') { ScalarIntrinsic.umin }
		else if name.starts_with('llvm.umax.i') { ScalarIntrinsic.umax }
		else if name.starts_with('llvm.abs.i') { ScalarIntrinsic.iabs }
		else if name.starts_with('llvm.sadd.sat.i') { ScalarIntrinsic.sadd_sat }
		else if name.starts_with('llvm.uadd.sat.i') { ScalarIntrinsic.uadd_sat }
		else if name.starts_with('llvm.ssub.sat.i') { ScalarIntrinsic.ssub_sat }
		else if name.starts_with('llvm.usub.sat.i') { ScalarIntrinsic.usub_sat }
		else if name.starts_with('llvm.sshl.sat.i') { ScalarIntrinsic.sshl_sat }
		else if name.starts_with('llvm.ushl.sat.i') { ScalarIntrinsic.ushl_sat }
		else { return error('AIR intrinsic: unsupported callee') }
	scalar_integer_intrinsic_width(name, id)!
	return id
}
// Inspect bytes directly: no substring allocation and no permissive numeric
// parser that might admit signs, leading zeroes, suffixes or other overloads.
fn scalar_integer_intrinsic_width(name string, id ScalarIntrinsic) !u32 {
	start := match id { .ctpop { 'llvm.ctpop.i'.len } .bitreverse { 'llvm.bitreverse.i'.len } .bswap { 'llvm.bswap.i'.len } .ctlz { 'llvm.ctlz.i'.len } .cttz { 'llvm.cttz.i'.len } .fshl { 'llvm.fshl.i'.len } .fshr { 'llvm.fshr.i'.len } .smin { 'llvm.smin.i'.len } .smax { 'llvm.smax.i'.len } .umin { 'llvm.umin.i'.len } .umax { 'llvm.umax.i'.len } .iabs { 'llvm.abs.i'.len } .sadd_sat { 'llvm.sadd.sat.i'.len } .uadd_sat { 'llvm.uadd.sat.i'.len } .ssub_sat { 'llvm.ssub.sat.i'.len } .usub_sat { 'llvm.usub.sat.i'.len } .sshl_sat { 'llvm.sshl.sat.i'.len } .ushl_sat { 'llvm.ushl.sat.i'.len } else { return error('AIR intrinsic: integer family') } }
	if name.len <= start || name.len > start + 2 || name[start] == `0` { return error('AIR intrinsic: integer overload spelling') }
	mut width := u32(0)
	for i in start .. name.len {
		if name[i] < `0` || name[i] > `9` { return error('AIR intrinsic: integer overload digits') }
		width = width * 10 + u32(name[i] - `0`)
	}
	if width < 1 || width > 64 || (id == .bswap && width % 16 != 0) { return error('AIR intrinsic: integer overload width') }
	return width
}
fn scalar_integer_intrinsic_value(id ScalarIntrinsic, bits u32, value u64) !u64 {
	if !scalar_integer_intrinsic(id) || scalar_integer_poison_flag(id) || scalar_integer_funnel(id) || scalar_integer_extremum(id) || scalar_integer_saturating(id) || scalar_integer_saturating_shift(id) || bits < 1 || bits > 64 || (id == .bswap && bits % 16 != 0) { return error('AIR intrinsic: unary integer operation/width') }
	mut input := value & constant_mask(bits); mut result := u64(0)
	if id == .bswap {
		for _ in 0 .. bits / 8 { result = (result << 8) | (input & 0xff); input >>= 8 }
	} else {
		for _ in 0 .. bits {
			if id == .ctpop { result += input & 1 } else { result = (result << 1) | (input & 1) }
			input >>= 1
		}
	}
	return result
}

fn scalar_integer_zero_count_value(id ScalarIntrinsic, bits u32, value u64, zero_poison u64) !IntegerValue {
	if !scalar_integer_zero_count(id) || bits < 1 || bits > 64 || zero_poison > 1 { return error('AIR intrinsic: zero count operation/width/flag') }
	input := value & constant_mask(bits)
	if input == 0 && zero_poison == 1 { return IntegerValue{poison: true} }
	mut count := u64(0)
	for i in u32(0) .. bits {
		shift := if id == .ctlz { bits - 1 - i } else { i }
		if input & (u64(1) << shift) != 0 { break }; count++
	}
	return IntegerValue{value: count}
}

fn scalar_integer_funnel_value(id ScalarIntrinsic, bits u32, a u64, b u64, amount u64) !u64 {
	if !scalar_integer_funnel(id) || bits < 1 || bits > 64 { return error('AIR intrinsic: funnel operation/width') }
	mask := constant_mask(bits); x := a & mask; y := b & mask
	shift := (amount & mask) % u64(bits)
	// The zero branch chooses opposite halves for left/right and prevents a
	// host shift by 64. Every shift below is between one and bits-1 inclusive.
	if shift == 0 { return if id == .fshl { x } else { y } }
	return (if id == .fshl { (x << shift) | (y >> (u64(bits) - shift)) } else { (x << (u64(bits) - shift)) | (y >> shift) }) & mask
}

fn scalar_integer_extremum_value(id ScalarIntrinsic, bits u32, a u64, b u64) !u64 {
	if !scalar_integer_extremum(id) || bits < 1 || bits > 64 { return error('AIR intrinsic: integer extremum operation/width') }
	mask := constant_mask(bits); x := a & mask; y := b & mask
	// Flipping the sign bit orders two's-complement patterns as unsigned keys,
	// including i1 and INT64_MIN, without conversion or signed arithmetic.
	key_flip := if id in [.smin, .smax]! { u64(1) << (bits - 1) } else { u64(0) }
	less := (x ^ key_flip) < (y ^ key_flip)
	minimum := id in [.smin, .umin]!
	return if less == minimum { x } else { y }
}

fn scalar_integer_abs_value(bits u32, value u64, minimum_poison u64) !IntegerValue {
	if bits < 1 || bits > 64 || minimum_poison > 1 { return error('AIR intrinsic: integer abs width/flag') }
	mask := constant_mask(bits); input := value & mask; sign := u64(1) << (bits - 1)
	if input == sign && minimum_poison == 1 { return IntegerValue{poison: true} }
	// Unsigned modular negation preserves INT_MIN when poison is disabled,
	// without ever negating a host signed minimum (including i1 and i64).
	return IntegerValue{value: if input & sign == 0 { input } else { (u64(0) - input) & mask }}
}
