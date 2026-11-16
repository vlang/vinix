// SPDX-License-Identifier: GPL-2.0-or-later
module airbitcode

// Append after the fourteen AIR integer identities without moving old slots.
const scalar_air_float_cache_base = scalar_air_integer_cache_base + 14

fn air_float_intrinsic(name string) !(ScalarIntrinsic, int) {
	return match name {
		'air.fabs.f32' { ScalarIntrinsic.fabs, 0 }
		'air.floor.f32' { ScalarIntrinsic.floor, 1 }
		'air.ceil.f32' { ScalarIntrinsic.ceil, 2 }
		'air.trunc.f32' { ScalarIntrinsic.trunc, 3 }
		else { return error('AIR intrinsic: unsupported AIR float overload') }
	}
}
