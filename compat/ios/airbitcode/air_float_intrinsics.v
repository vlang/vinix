// SPDX-License-Identifier: GPL-2.0-or-later
module airbitcode

// Append after the fourteen AIR integer identities without moving old slots.
const scalar_air_float_cache_base = scalar_air_integer_cache_base + 14

// Keep the existing float32 and integer keys stable when admitting half calls.
const scalar_air_half_float_cache_base = scalar_air_i64_integer_cache_base + 14

fn air_float_intrinsic(name string) !(ScalarIntrinsic, int) {
	return match name {
		'air.fabs.f32' { ScalarIntrinsic.fabs, 0 }
		'air.floor.f32' { ScalarIntrinsic.floor, 1 }
		'air.ceil.f32' { ScalarIntrinsic.ceil, 2 }
		'air.trunc.f32' { ScalarIntrinsic.trunc, 3 }
		'air.sqrt.f32' { ScalarIntrinsic.sqrt, 4 }
		'air.round.f32' { ScalarIntrinsic.round, 5 }
		'air.rint.f32' { ScalarIntrinsic.rint, 6 }
		'air.fma.f32' { ScalarIntrinsic.fma, 7 }
		'air.fmin.f32' { ScalarIntrinsic.air_fmin, 8 }
		'air.fmax.f32' { ScalarIntrinsic.air_fmax, 9 }
		'air.clamp.f32' { ScalarIntrinsic.air_clamp, 10 }
		'air.fabs.f16' { ScalarIntrinsic.fabs, scalar_air_half_float_cache_base - scalar_air_float_cache_base }
		'air.floor.f16' { ScalarIntrinsic.floor, scalar_air_half_float_cache_base - scalar_air_float_cache_base + 1 }
		'air.ceil.f16' { ScalarIntrinsic.ceil, scalar_air_half_float_cache_base - scalar_air_float_cache_base + 2 }
		'air.trunc.f16' { ScalarIntrinsic.trunc, scalar_air_half_float_cache_base - scalar_air_float_cache_base + 3 }
		else { return error('AIR intrinsic: unsupported AIR float overload') }
	}
}
