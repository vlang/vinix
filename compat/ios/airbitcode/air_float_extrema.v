// SPDX-License-Identifier: GPL-2.0-or-later
module airbitcode

// MSL fmin/fmax return the first argument on a numeric tie, including mixed
// signed zeros. Keep that choice separate from LLVM's existing zero ordering.
fn scalar_air_float_extremum(id ScalarIntrinsic, bits u32, a u64, b u64) !u64 {
	if id !in [.air_fmin, .air_fmax]! || bits != 32 {
		return error('AIR float extremum: float32 binary family required')
	}
	x := u64(u32(a)); y := u64(u32(b))
	if x & 0x7fffffff == 0 && y & 0x7fffffff == 0 { return x }
	return scalar_intrinsic_value(if id == .air_fmin { ScalarIntrinsic.minnum } else { ScalarIntrinsic.maxnum }, bits, x, y)!
}
