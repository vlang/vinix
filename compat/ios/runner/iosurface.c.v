// SPDX-License-Identifier: GPL-2.0-or-later
module main

// Local IOSurface storage is shared across fork and independently retainable.
// Mach-port export, global IDs and device-specific allocation are separate APIs.
fn cv_pixel_surface(object u64) u64 { return cv_pixel_state(object).surface }
fn cv_surface_type_id() u64 { return ios_runtime.names['VinixIOSurface'] }
fn cv_surface_state(object u64) &CVPixelState {
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	header := ios_runtime.objects[object] or { panic('iOS: expected a live IOSurface') }
	if header.cls != cv_surface_type_id() || header.cv_pixel == unsafe { nil } { panic('iOS: expected a live IOSurface') }
	return header.cv_pixel
}
fn cv_surface_width(object u64) u64 { return cv_surface_state(object).width }
fn cv_surface_height(object u64) u64 { return cv_surface_state(object).height }
fn cv_surface_base(object u64) u64 { return cv_surface_state(object).base }
fn cv_surface_format(object u64) u32 { return cv_surface_state(object).format }
fn cv_surface_count(object u64) u64 { return cv_surface_state(object).planes }
fn cv_surface_size(object u64) u64 {
	state := cv_surface_state(object)
	page := u64(C.getpagesize())
	return (state.size + page - 1) / page * page
}
fn cv_surface_row(object u64) u64 { return cv_surface_state(object).stride }
fn cv_surface_element(object u64) u64 { return if cv_surface_state(object).planes == 0 { u64(4) } else { u64(1) } }
fn cv_surface_plane_width(object u64, index u64) u64 { state := cv_surface_state(object); if state.planes == 0 { return if index == 0 { state.width } else { u64(0) } }; return if index < state.planes { state.widths[int(index)] } else { u64(0) } }
fn cv_surface_plane_height(object u64, index u64) u64 { state := cv_surface_state(object); if state.planes == 0 { return if index == 0 { state.height } else { u64(0) } }; return if index < state.planes { state.heights[int(index)] } else { u64(0) } }
fn cv_surface_plane_row(object u64, index u64) u64 { state := cv_surface_state(object); if state.planes == 0 { return if index == 0 { state.stride } else { u64(0) } }; return if index < state.planes { state.strides[int(index)] } else { u64(0) } }
fn cv_surface_plane_base(object u64, index u64) u64 { state := cv_surface_state(object); if state.planes == 0 { return if index == 0 { state.base } else { u64(0) } }; return if index < state.planes { state.addresses[int(index)] } else { u64(0) } }
fn cv_surface_plane_element(object u64, index u64) u64 { state := cv_surface_state(object); if state.planes == 0 { return if index == 0 { u64(4) } else { u64(0) } }; return if index == 0 { u64(1) } else if index == 1 { u64(2) } else { u64(0) } }
fn iosurface_symbol(symbol string) ?u64 {
	return match symbol {
		'_IOSurfaceGetTypeID' { u64(unsafe { voidptr(cv_surface_type_id) }) }
		'_IOSurfaceGetWidth' { u64(unsafe { voidptr(cv_surface_width) }) }
		'_IOSurfaceGetHeight' { u64(unsafe { voidptr(cv_surface_height) }) }
		'_IOSurfaceGetBaseAddress' { u64(unsafe { voidptr(cv_surface_base) }) }
		'_IOSurfaceGetPixelFormat' { u64(unsafe { voidptr(cv_surface_format) }) }
		'_IOSurfaceGetPlaneCount' { u64(unsafe { voidptr(cv_surface_count) }) }
		'_IOSurfaceGetAllocSize' { u64(unsafe { voidptr(cv_surface_size) }) }
		'_IOSurfaceGetBytesPerRow' { u64(unsafe { voidptr(cv_surface_row) }) }
		'_IOSurfaceGetBytesPerElement' { u64(unsafe { voidptr(cv_surface_element) }) }
		'_IOSurfaceGetWidthOfPlane' { u64(unsafe { voidptr(cv_surface_plane_width) }) }
		'_IOSurfaceGetHeightOfPlane' { u64(unsafe { voidptr(cv_surface_plane_height) }) }
		'_IOSurfaceGetBytesPerRowOfPlane' { u64(unsafe { voidptr(cv_surface_plane_row) }) }
		'_IOSurfaceGetBytesPerElementOfPlane' { u64(unsafe { voidptr(cv_surface_plane_element) }) }
		'_IOSurfaceGetBaseAddressOfPlane' { u64(unsafe { voidptr(cv_surface_plane_base) }) }
		else { none }
	}
}
