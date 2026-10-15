// SPDX-License-Identifier: GPL-2.0-or-later
module main

// CPU storage is borrowed until the final CF/ObjC release invokes its owner.
// No GPU coherence, IOSurface mapping or Metal texture is implied by this type.
struct CVPixelState {
mut:
	width u64
	height u64
	format u32
	planes u64
	base u64
	size u64
	stride u64
	addresses [2]u64
	widths [2]u64
	heights [2]u64
	strides [2]u64
	callback u64
	context u64
}

fn cv_pixel_type_id() u64 { return ios_runtime.names['VinixCVPixelBuffer'] }

fn cv_pixel_state(object u64) &CVPixelState {
	if ios_runtime == unsafe { nil } { panic('iOS: CoreVideo requires an initialized runtime') }
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	header := ios_runtime.objects[object] or { panic('iOS: expected a live CPU CVPixelBuffer') }
	if header.cls != cv_pixel_type_id() || header.cv_pixel == unsafe { nil } { panic('iOS: expected a live CPU CVPixelBuffer') }
	return header.cv_pixel
}

fn cv_pixel_attributes(allocator u64, attributes u64) {
	cf_allocator_check(allocator)
	if attributes != 0 && (!objc_is_kind(attributes, ios_runtime.names['NSDictionary']) || obj_header(attributes).items.len != 0) {
		panic('iOS: CPU CVPixelBuffer wrapping supports nil or empty attributes')
	}
}

fn cv_pixel_create_bytes(allocator u64, width u64, height u64, format u32, base u64, stride u64, callback u64, context u64, attributes u64, output &u64) i32 {
	if output == unsafe { nil } || width == 0 || height == 0 || base == 0 || stride == 0 || stride > ~u64(0) / height { return -6661 }
	if format != 0x42475241 { return -6680 } // BGRA; other packed formats need individual layouts.
	cv_pixel_attributes(allocator, attributes)
	mut state := unsafe { &CVPixelState(C.calloc(1, sizeof(CVPixelState))) }
	if state == unsafe { nil } { return -6662 }
	state.width = width; state.height = height; state.format = format
	state.base = base; state.stride = stride; state.size = stride * height
	state.callback = callback; state.context = context
	object := objc_allocate(cv_pixel_type_id())
	obj_header(object).cv_pixel = state
	unsafe { *output = object }
	return 0
}

fn cv_pixel_create_planar(allocator u64, width u64, height u64, format u32, data u64, size u64, count u64, addresses &u64, widths &u64, heights &u64, strides &u64, callback u64, context u64, attributes u64, output &u64) i32 {
	if output == unsafe { nil } || width == 0 || height == 0 || count != 2 || addresses == unsafe { nil } || widths == unsafe { nil } || heights == unsafe { nil } || strides == unsafe { nil } { return -6661 }
	if format !in [u32(0x34323076), 0x34323066]! { return -6680 } // 420v/420f, two caller-supplied planes.
	for i in 0 .. 2 { unsafe { if addresses[i] == 0 || widths[i] == 0 || heights[i] == 0 || strides[i] == 0 || strides[i] > ~u64(0) / heights[i] { return -6661 } } }
	cv_pixel_attributes(allocator, attributes)
	mut state := unsafe { &CVPixelState(C.calloc(1, sizeof(CVPixelState))) }
	if state == unsafe { nil } { return -6662 }
	state.width = width; state.height = height; state.format = format; state.planes = 2
	state.base = data; state.size = size; state.stride = size / height
	for i in 0 .. 2 { unsafe { state.addresses[i] = addresses[i]; state.widths[i] = widths[i]; state.heights[i] = heights[i]; state.strides[i] = strides[i] } }
	state.callback = callback; state.context = context
	object := objc_allocate(cv_pixel_type_id())
	obj_header(object).cv_pixel = state
	unsafe { *output = object }
	return 0
}

type CVReleaseBytes = fn (u64, u64)
type CVReleasePlanes = fn (u64, u64, u64, u64, &u64)
fn cv_pixel_dispose(mut header ObjHeader) {
	mut state := header.cv_pixel
	if state == unsafe { nil } { return }
	callback := state.callback
	state.callback = 0 // Keep metadata/plane addresses readable throughout the callback.
	if callback != 0 {
		if state.planes == 0 { unsafe { CVReleaseBytes(voidptr(callback))(state.context, state.base) } }
		else { unsafe { CVReleasePlanes(voidptr(callback))(state.context, state.base, state.size, state.planes, &state.addresses[0]) } }
	}
	header.cv_pixel = unsafe { nil }
	C.free(state)
}

fn cv_pixel_retain(object u64) u64 { if object == 0 { return 0 }; cv_pixel_state(object); return objc_retain(object) }
fn cv_pixel_release(object u64) { if object == 0 { return }; cv_pixel_state(object); objc_release(object) }
fn cv_pixel_width(object u64) u64 { return cv_pixel_state(object).width }
fn cv_pixel_height(object u64) u64 { return cv_pixel_state(object).height }
fn cv_pixel_format(object u64) u32 { return cv_pixel_state(object).format }
fn cv_pixel_base(object u64) u64 { return cv_pixel_state(object).base }
fn cv_pixel_stride(object u64) u64 { return cv_pixel_state(object).stride }
fn cv_pixel_size(object u64) u64 { return cv_pixel_state(object).size }
fn cv_pixel_planar(object u64) u8 { return u8(cv_pixel_state(object).planes != 0) }
fn cv_pixel_plane_count(object u64) u64 { return cv_pixel_state(object).planes }
// Native packed BGRA exposes its width/height/stride for plane zero, despite
// the older SDK wording; an out-of-range plane always has zero geometry.
fn cv_pixel_plane_width(object u64, index u64) u64 {
	state := cv_pixel_state(object)
	if state.planes == 0 { return if index == 0 { state.width } else { u64(0) } }
	return if index < state.planes { state.widths[int(index)] } else { u64(0) }
}
fn cv_pixel_plane_height(object u64, index u64) u64 {
	state := cv_pixel_state(object)
	if state.planes == 0 { return if index == 0 { state.height } else { u64(0) } }
	return if index < state.planes { state.heights[int(index)] } else { u64(0) }
}
fn cv_pixel_plane_stride(object u64, index u64) u64 {
	state := cv_pixel_state(object)
	if state.planes == 0 { return if index == 0 { state.stride } else { u64(0) } }
	return if index < state.planes { state.strides[int(index)] } else { u64(0) }
}
fn cv_pixel_plane_base(object u64, index u64) u64 {
	state := cv_pixel_state(object)
	if state.planes == 0 { return if index == 0 { state.base } else { u64(0) } }
	return if index < state.planes { state.addresses[int(index)] } else { u64(0) }
}
fn cv_pixel_lock(object u64, flags u64) i32 {
	_ = flags
	cv_pixel_state(object)
	// Borrowed CPU memory is permanently mapped. These are accessibility/cache
	// operations, not a mutual-exclusion lock; even reserved flags are ignored
	// by native CPU-backed buffers. There is no device cache to synchronize.
	return 0
}

fn corevideo_symbol(symbol string) ?u64 {
	return match symbol {
		'_CVPixelBufferGetTypeID' { u64(unsafe { voidptr(cv_pixel_type_id) }) }
		'_CVPixelBufferCreateWithBytes' { u64(unsafe { voidptr(cv_pixel_create_bytes) }) }
		'_CVPixelBufferCreateWithPlanarBytes' { u64(unsafe { voidptr(cv_pixel_create_planar) }) }
		'_CVPixelBufferRetain' { u64(unsafe { voidptr(cv_pixel_retain) }) }
		'_CVPixelBufferRelease' { u64(unsafe { voidptr(cv_pixel_release) }) }
		'_CVPixelBufferGetWidth' { u64(unsafe { voidptr(cv_pixel_width) }) }
		'_CVPixelBufferGetHeight' { u64(unsafe { voidptr(cv_pixel_height) }) }
		'_CVPixelBufferGetPixelFormatType' { u64(unsafe { voidptr(cv_pixel_format) }) }
		'_CVPixelBufferGetBaseAddress' { u64(unsafe { voidptr(cv_pixel_base) }) }
		'_CVPixelBufferGetBytesPerRow' { u64(unsafe { voidptr(cv_pixel_stride) }) }
		'_CVPixelBufferGetDataSize' { u64(unsafe { voidptr(cv_pixel_size) }) }
		'_CVPixelBufferIsPlanar' { u64(unsafe { voidptr(cv_pixel_planar) }) }
		'_CVPixelBufferGetPlaneCount' { u64(unsafe { voidptr(cv_pixel_plane_count) }) }
		'_CVPixelBufferGetWidthOfPlane' { u64(unsafe { voidptr(cv_pixel_plane_width) }) }
		'_CVPixelBufferGetHeightOfPlane' { u64(unsafe { voidptr(cv_pixel_plane_height) }) }
		'_CVPixelBufferGetBytesPerRowOfPlane' { u64(unsafe { voidptr(cv_pixel_plane_stride) }) }
		'_CVPixelBufferGetBaseAddressOfPlane' { u64(unsafe { voidptr(cv_pixel_plane_base) }) }
		'_CVPixelBufferLockBaseAddress', '_CVPixelBufferUnlockBaseAddress' { u64(unsafe { voidptr(cv_pixel_lock) }) }
		else { none }
	}
}
