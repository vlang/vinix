// SPDX-License-Identifier: GPL-2.0-or-later
module airbitcode

// AIR and LLVM declarations may coexist. Keep their reserved identities distinct
// even though these two AIR operations share the existing integer evaluators.
const scalar_air_integer_cache_base = scalar_mulh_cache_base + 128

fn air_integer_intrinsic(name string) !(ScalarIntrinsic, int) {
	return match name {
		'air.popcount.i32' { ScalarIntrinsic.ctpop, 0 }
		'air.reverse_bits.i32' { ScalarIntrinsic.bitreverse, 1 }
		else { return error('AIR intrinsic: unsupported AIR integer overload') }
	}
}
