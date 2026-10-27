// SPDX-License-Identifier: GPL-2.0-or-later
module main

// Metal permits nil when no device is available. The GLES renderer cannot
// execute Metal command buffers or AIR shaders, so it is not a Metal device.
// Keep this result nil until a working Metal backend can supply the device.
fn metal_create_system_default_device() u64 {
	return 0
}

fn metal_device_symbol(symbol string) ?u64 {
	return match symbol {
		'_MTLCreateSystemDefaultDevice' { u64(unsafe { voidptr(metal_create_system_default_device) }) }
		else { none }
	}
}
