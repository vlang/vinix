// SPDX-License-Identifier: GPL-2.0-or-later
module airbitcode

// AIR and LLVM declarations may coexist. Keep their reserved identities distinct
// even though these AIR operations share the existing integer evaluators.
const scalar_air_integer_cache_base = scalar_mulh_cache_base + 128
// Append i64 identities after the existing AIR float identities.
const scalar_air_i64_integer_cache_base = scalar_air_float_cache_base + 11

fn air_integer_intrinsic(name string) !(ScalarIntrinsic, int) {
	return match name {
		'air.popcount.i32' { ScalarIntrinsic.ctpop, 0 }
		'air.reverse_bits.i32' { ScalarIntrinsic.bitreverse, 1 }
		'air.min.s.i32' { ScalarIntrinsic.smin, 2 }
		'air.max.s.i32' { ScalarIntrinsic.smax, 3 }
		'air.min.u.i32' { ScalarIntrinsic.umin, 4 }
		'air.max.u.i32' { ScalarIntrinsic.umax, 5 }
		'air.clz.i32' { ScalarIntrinsic.ctlz, 6 }
		'air.ctz.i32' { ScalarIntrinsic.cttz, 7 }
		'air.add_sat.s.i32' { ScalarIntrinsic.sadd_sat, 8 }
		'air.sub_sat.s.i32' { ScalarIntrinsic.ssub_sat, 9 }
		'air.add_sat.u.i32' { ScalarIntrinsic.uadd_sat, 10 }
		'air.sub_sat.u.i32' { ScalarIntrinsic.usub_sat, 11 }
		'air.mul_hi.s.i32' { ScalarIntrinsic.smulh, 12 }
		'air.mul_hi.u.i32' { ScalarIntrinsic.umulh, 13 }
		'air.popcount.i64' { ScalarIntrinsic.ctpop, scalar_air_i64_integer_cache_base - scalar_air_integer_cache_base }
		'air.reverse_bits.i64' { ScalarIntrinsic.bitreverse, scalar_air_i64_integer_cache_base - scalar_air_integer_cache_base + 1 }
		else { return error('AIR intrinsic: unsupported AIR integer overload') }
	}
}
