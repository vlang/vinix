// SPDX-License-Identifier: GPL-2.0-or-later
module main

// The software backend executes shared-resource blits and bounded scalar compute. Keep it
// opt-in; the ordinary runner cannot yet execute an application's Metal shaders.
fn metal_create_system_default_device() u64 {
	$if ios_metal_software ? {
		return sm_new('VinixSoftwareMTLDevice', 0)
	}
	return 0
}

fn metal_device_symbol(symbol string) ?u64 {
	return match symbol {
		'_MTLCreateSystemDefaultDevice' { u64(unsafe { voidptr(metal_create_system_default_device) }) }
		'_MTLLibraryErrorDomain' { framework_string_constant(symbol, 'MTLLibraryErrorDomain') }
		'_MTLCommandBufferErrorDomain' { framework_string_constant(symbol, 'MTLCommandBufferErrorDomain') }
		else { none }
	}
}
