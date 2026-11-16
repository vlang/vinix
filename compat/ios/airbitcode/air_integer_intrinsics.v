// SPDX-License-Identifier: GPL-2.0-or-later
module airbitcode

// AIR and LLVM declarations may coexist. Keep their reserved identities distinct
// even though these AIR operations share the existing integer evaluators.
const scalar_air_integer_cache_base = scalar_mulh_cache_base + 128

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
		else { return error('AIR intrinsic: unsupported AIR integer overload') }
	}
}
