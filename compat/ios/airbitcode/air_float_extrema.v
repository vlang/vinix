// SPDX-License-Identifier: GPL-2.0-or-later
module airbitcode

// MSL fmin/fmax return the first argument on a numeric tie, including mixed
// signed zeros. Keep that choice separate from LLVM's existing zero ordering.
fn scalar_air_float_extremum(id ScalarIntrinsic, bits u32, a u64, b u64) !u64 {
	if id !in [.air_fmin, .air_fmax]! || bits !in [u32(16), 32]! {
		return error('AIR float extremum: half/float binary family required')
	}
	mask := constant_mask(bits); magnitude := (u64(1) << (bits - 1)) - 1
	x := a & mask; y := b & mask
	if x & magnitude == 0 && y & magnitude == 0 { return x }
	return scalar_intrinsic_value(if id == .air_fmin { ScalarIntrinsic.minnum } else { ScalarIntrinsic.maxnum }, bits, x, y)!
}
