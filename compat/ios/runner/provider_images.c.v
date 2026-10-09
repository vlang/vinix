// SPDX-License-Identifier: GPL-2.0-or-later
// Borrowed provider buffers and immutable RGB images. Native Mac libraries
// are behavioral references; all ownership and pixel interpretation is V.
module main

import math

fn C.ios_cg_image_create()

type CGProviderRelease = fn (voidptr, voidptr, u64)

fn cg_provider_create(info voidptr, data voidptr, size u64, release u64) u64 {
	if data == unsafe { nil } || size == 0 || size > 128 * 1024 * 1024 { return 0 }
	provider := objc_allocate(ios_runtime.names['VinixCGDataProvider'])
	mut header := obj_header(provider)
	header.external_data = u64(data)
	header.external_size = size
	header.provider_info = info
	header.provider_release = release
	return provider
}

fn cg_provider_dispose(object u64) {
	mut header := obj_header(object)
	callback := header.provider_release
	header.provider_release = 0
	if callback != 0 {
		// No runtime lock is held: app code may create/release other providers.
		unsafe { CGProviderRelease(voidptr(callback))(header.provider_info, voidptr(header.external_data), header.external_size) }
	}
}

fn cg_provider_cfdata(data u64) u64 {
	if data == 0 { return 0 }
	provider := cg_provider_create(unsafe { nil }, unsafe { voidptr(data_pointer(data)) }, data_length(data), 0)
	if provider != 0 { store_field(provider, 0, data) }
	return provider
}

fn cg_copy_bytes(bytes u64, size u64) u64 {
	if size > 128 * 1024 * 1024 || (size != 0 && bytes == 0) { return 0 }
	data := objc_allocate(ios_runtime.names['NSData'])
	mut header := obj_header(data)
	header.data = []u8{len: int(size)}
	header.data.flags |= .noslices
	if size != 0 { unsafe { C.memcpy(header.data.data, voidptr(bytes), usize(size)) } }
	return data
}

fn cg_provider_data(provider u64) u64 {
	if provider == 0 { return 0 }
	// Mac's direct provider copies share immutable bytes and keep the provider
	// alive. Preserve that observable callback lifetime, including CFData-backed
	// providers; releasing the image alone cannot invalidate a returned CFData.
	data := objc_allocate(ios_runtime.names['NSData'])
	mut header := obj_header(data)
	header.external_data = data_pointer(provider)
	header.external_size = data_length(provider)
	store_field(data, 0, provider)
	return data
}

fn cg_provider_id() u64 { return ios_runtime.names['VinixCGDataProvider'] }
fn cg_image_id() u64 { return ios_runtime.names['VinixCGImage'] }

@[export: 'ios_cg_image_create_native']
fn cg_image_create(width u64, height u64, bits u64, pixel_bits u64, stride u64, space u64, info u32, provider u64, decode &f64, interpolate bool, intent u32) u64 {
	alpha := info & 31
	order := info & 0x7000
	if width == 0 || height == 0 || width > 8192 || height > 8192 || bits != 8 || space == 0 || cg_space_model(space) != 1 || provider == 0 || intent > 4 || info & ~u32(0x7007) != 0 {
		return 0
	}
	if (pixel_bits == 24 && (alpha != 0 || order != 0)) || (pixel_bits == 32 && (alpha !in [u32(1), 2, 3, 4, 5, 6] || order !in [u32(0), 0x2000, 0x4000])) || pixel_bits !in [u64(24), 32] {
		return 0
	}
	minimum := width * (pixel_bits / 8)
	if stride < minimum || stride > 128 * 1024 * 1024 / height || data_length(provider) < stride * (height - 1) + minimum { return 0 }
	mut values := [6]f64{}
	if decode != unsafe { nil } {
		for index in 0 .. 6 {
			values[index] = unsafe { decode[index] }
			if !math.is_finite(values[index]) { return 0 }
		}
	}
	mut state := unsafe { &BitmapState(C.calloc(1, sizeof(BitmapState))) }
	if state == unsafe { nil } { return 0 }
	state.info = info
	state.pixel_bits = u32(pixel_bits)
	state.scale = 1
	state.has_decode = decode != unsafe { nil }
	state.decode = values
	state.should_interpolate = interpolate
	state.intent = intent
	state.saved = []BitmapPaint{}
	state.saved.flags |= .noslices
	image := objc_allocate(ios_runtime.names['VinixCGImage'])
	mut header := obj_header(image)
	header.bitmap = state
	header.external_data = data_pointer(provider)
	header.external_size = data_length(provider)
	header.number = i64(stride)
	header.frame.width = f64(width)
	header.frame.height = f64(height)
	store_field(image, 0, space)
	store_field(image, 1, provider)
	return image
}

fn cg_image_decode(image u64) &f64 {
	if image == 0 { return unsafe { nil } }
	state := bitmap_state(image)
	return if state.has_decode { unsafe { &state.decode[0] } } else { unsafe { nil } }
}

fn cg_image_interpolate(image u64) bool { return image != 0 && bitmap_state(image).should_interpolate }
fn cg_image_intent(image u64) u32 { return if image == 0 { u32(0) } else { bitmap_state(image).intent } }

fn provider_image_symbol(symbol string) ?u64 {
	return match symbol {
		'_CGDataProviderCreateWithData' { u64(unsafe { voidptr(cg_provider_create) }) }
		'_CGDataProviderCreateWithCFData' { u64(unsafe { voidptr(cg_provider_cfdata) }) }
		'_CGDataProviderGetTypeID' { u64(unsafe { voidptr(cg_provider_id) }) }
		'_CGImageGetTypeID' { u64(unsafe { voidptr(cg_image_id) }) }
		'_CGImageCreate' { u64(unsafe { voidptr(C.ios_cg_image_create) }) }
		'_CGImageGetDecode' { u64(unsafe { voidptr(cg_image_decode) }) }
		'_CGImageGetShouldInterpolate' { u64(unsafe { voidptr(cg_image_interpolate) }) }
		'_CGImageGetRenderingIntent' { u64(unsafe { voidptr(cg_image_intent) }) }
		else { return none }
	}
}
