// SPDX-License-Identifier: GPL-2.0-or-later
// Independent V bitmap state, compositing and UIKit context ownership.
module main

import math

struct ObjSize {
	width  f64
	height f64
}

struct ObjTransform {
	a  f64
	b  f64
	c  f64
	d  f64
	tx f64
	ty f64
}

struct BitmapPaint {
mut:
	matrix        ObjTransform
	clip          ObjRect // Device pixels with a top-left origin.
	color         u32
	fill_alpha    f64
	alpha         f64
	interpolation u32
	fill_components u32 = 3
}

struct BitmapState {
mut:
	info  u32
	scale f64
	paint BitmapPaint
	saved []BitmapPaint
}

struct ImageContextEntry {
	context u64
	image   bool
}

struct ImageContextStack {
mut:
	entries []ImageContextEntry
}

fn bitmap_state(object u64) &BitmapState {
	state := obj_header(object).bitmap
	if state == unsafe { nil } { panic('iOS: expected a supported bitmap object') }
	return state
}

fn bitmap_dispose(object u64) {
	state := obj_header(object).bitmap
	if state != unsafe { nil } {
		unsafe { state.saved.free() }
		C.free(state)
	}
}

fn cg_bitmap_create(data voidptr, width u64, height u64, bits u64, stride u64, space u64, info u32) u64 {
	if bits != 8 || info !in [u32(1), 5, 0x2002, 0x2006] || space == 0 || cg_space_model(space) != 1 || width == 0 || height == 0 || width > 8192 || height > 8192 {
		return 0
	}
	row := if stride == 0 { (width * 4 + 15) & ~u64(15) } else { stride }
	if row < width * 4 || row > 128 * 1024 * 1024 / height { return 0 }
	context := objc_allocate(ios_runtime.names['VinixCGContext'])
	mut header := obj_header(context)
	header.external_data = u64(data)
	header.external_size = row * height
	header.number = i64(row)
	header.frame.width = f64(width)
	header.frame.height = f64(height)
	header.color = 0
	header.real_number = 1
	if data == unsafe { nil } {
		header.external_data = u64(C.calloc(usize(height), usize(row)))
		header.free_data = true
		if header.external_data == 0 {
			objc_release(context)
			return 0
		}
	}
	mut state := unsafe { &BitmapState(C.calloc(1, sizeof(BitmapState))) }
	if state == unsafe { nil } {
		objc_release(context)
		return 0
	}
	state.info = info
	state.scale = 1
	state.paint = BitmapPaint{ matrix: ObjTransform{1, 0, 0, 1, 0, 0}, clip: ObjRect{0, 0, f64(width), f64(height)}, fill_alpha: 1, alpha: 1 }
	state.saved = []BitmapPaint{}
	state.saved.flags |= .noslices
	header.bitmap = state
	store_field(context, 0, space)
	return context
}

fn cg_rgb_space() u64 { return cg_space_create(1) }

fn cg_set_fill(context u64, color u64) {
	if context == 0 || color == 0 { return }
	mut header := obj_header(context)
	header.color = obj_header(color).color
	header.real_number = obj_header(color).real_number
	mut state := bitmap_state(context)
	state.paint.color = header.color
	state.paint.fill_alpha = header.real_number
	state.paint.fill_components = u32(cg_space_components(cg_color_space(color)))
}

fn cg_set_stroke(context u64, color u64) { if context != 0 { store_field(context, 2, color) } }

fn cg_text_position(context u64, x f64, y f64) {
	if !math.is_finite(x) || !math.is_finite(y) { panic('iOS: invalid bitmap text position') }
	mut header := obj_header(context)
	header.frame.x = x
	header.frame.y = y
}

fn bitmap_component(value f64) u32 { return u32(math.round(math.max(0, math.min(1, value)) * 255)) }

fn cg_rgb_fill(context u64, red f64, green f64, blue f64, alpha f64) {
	if context == 0 { return }
	mut header := obj_header(context)
	header.color = bitmap_component(red) << 16 | bitmap_component(green) << 8 | bitmap_component(blue)
	header.real_number = math.max(0, math.min(1, alpha))
	mut state := bitmap_state(context)
	state.paint.color = header.color
	state.paint.fill_alpha = header.real_number
}

fn cg_rgb_fill_components(context u64, red f64, green f64, blue f64, alpha f64) {
	cg_rgb_fill(context, red, green, blue, alpha)
	if context != 0 { mut state := bitmap_state(context); state.paint.fill_components = 3 }
}

fn cg_alpha(context u64, alpha f64) {
	mut state := bitmap_state(context)
	state.paint.alpha = math.max(0, math.min(1, alpha))
}

fn cg_interpolation(context u64, quality u32) {
	mut state := bitmap_state(context)
	if quality > 4 { panic('iOS: invalid image interpolation quality') }
	state.paint.interpolation = quality
}

fn cg_ctm(context u64) ObjTransform { return bitmap_state(context).paint.matrix }

fn cg_translate(context u64, x f64, y f64) {
	mut state := bitmap_state(context)
	m := state.paint.matrix
	state.paint.matrix = ObjTransform{m.a, m.b, m.c, m.d, m.tx + m.a * x + m.c * y, m.ty + m.b * x + m.d * y}
}

fn cg_scale(context u64, x f64, y f64) {
	mut state := bitmap_state(context)
	m := state.paint.matrix
	state.paint.matrix = ObjTransform{m.a * x, m.b * x, m.c * y, m.d * y, m.tx, m.ty}
}

fn cg_save(context u64) {
	mut state := bitmap_state(context)
	if state.saved.len >= 256 { panic('iOS: bitmap state stack limit exceeded') }
	state.saved << state.paint
}

fn cg_restore(context u64) {
	mut state := bitmap_state(context)
	if state.saved.len == 0 { return }
	state.paint = state.saved.pop()
	mut header := obj_header(context)
	header.color = state.paint.color
	header.real_number = state.paint.fill_alpha
}

fn bitmap_rect(context u64, rect ObjRect) ObjRect {
	m := bitmap_state(context).paint.matrix
	if m.b != 0 || m.c != 0 { panic('iOS: rotated/sheared bitmap drawing is not implemented') }
	x0 := rect.x * m.a + m.tx
	x1 := (rect.x + rect.width) * m.a + m.tx
	y0 := obj_header(context).frame.height - (rect.y * m.d + m.ty)
	y1 := obj_header(context).frame.height - ((rect.y + rect.height) * m.d + m.ty)
	for value in [x0, x1, y0, y1]! {
		if !math.is_finite(value) { panic('iOS: invalid bitmap rectangle') }
	}
	return ObjRect{math.min(x0, x1), math.min(y0, y1), math.abs(x1 - x0), math.abs(y1 - y0)}
}

fn bitmap_intersection(left ObjRect, right ObjRect) ObjRect {
	x := math.max(left.x, right.x)
	y := math.max(left.y, right.y)
	return ObjRect{x, y, math.max(0, math.min(left.x + left.width, right.x + right.width) - x), math.max(0, math.min(left.y + left.height, right.y + right.height) - y)}
}

fn cg_clip(context u64, rect ObjRect) {
	mut state := bitmap_state(context)
	state.paint.clip = bitmap_intersection(state.paint.clip, bitmap_rect(context, rect))
}

fn bitmap_pixel(object u64, x int, y int) [4]u32 {
	header := obj_header(object)
	state := bitmap_state(object)
	p := unsafe { &u8(header.external_data + u64(i64(y) * header.number + i64(x) * 4)) }
	blue_first := state.info & 0x2000 != 0
	return unsafe { [u32(p[if blue_first { 2 } else { 0 }]), u32(p[1]),
		u32(p[if blue_first { 0 } else { 2 }]),
		if state.info & 15 in [u32(5), 6] { u32(255) } else { u32(p[3]) }]! }
}

fn bitmap_blend(context u64, x int, y int, source [4]u32) {
	header := obj_header(context)
	state := bitmap_state(context)
	p := unsafe { &u8(header.external_data + u64(i64(y) * header.number + i64(x) * 4)) }
	destination := bitmap_pixel(context, x, y)
	for channel in 0 .. 4 {
		if channel == 3 && state.info & 15 in [u32(5), 6] { continue }
		index := if state.info & 0x2000 != 0 && channel != 1 && channel != 3 {
			2 - channel
		} else {
			channel
		}
		unsafe { p[index] = u8(math.min(u32(255), source[channel] + (destination[channel] * (255 - source[3]) + 127) / 255)) }
	}
}

fn cg_fill_rect(context u64, rect ObjRect) {
	if context == 0 { return }
	state := bitmap_state(context)
	r := bitmap_intersection(bitmap_rect(context, rect), state.paint.clip)
	if r.width <= 0 || r.height <= 0 { return }
	for y := int(math.floor(r.y)); y < int(math.ceil(r.y + r.height)); y++ {
		for x := int(math.floor(r.x)); x < int(math.ceil(r.x + r.width)); x++ {
			coverage := (math.min(f64(x + 1), r.x + r.width) - math.max(f64(x), r.x)) * (math.min(f64(y + 1), r.y + r.height) - math.max(f64(y), r.y))
			alpha := bitmap_component(state.paint.fill_alpha * state.paint.alpha * coverage)
			bitmap_blend(context, x, y, [
				((state.paint.color >> 16) & 255) * alpha / 255,
				((state.paint.color >> 8) & 255) * alpha / 255,
				(state.paint.color & 255) * alpha / 255,
				alpha,
			]!)
		}
	}
}

fn cg_clear_rect(context u64, rect ObjRect) {
	state := bitmap_state(context)
	r := bitmap_intersection(bitmap_rect(context, rect), state.paint.clip)
	if r.width <= 0 || r.height <= 0 { return }
	header := obj_header(context)
	for y := int(math.floor(r.y)); y < int(math.ceil(r.y + r.height)); y++ {
		for x := int(math.floor(r.x)); x < int(math.ceil(r.x + r.width)); x++ {
			// Preserve partial coverage at fractional rectangle edges.
			coverage := (math.min(f64(x + 1), r.x + r.width) - math.max(f64(x), r.x)) * (math.min(f64(y + 1), r.y + r.height) - math.max(f64(y), r.y))
			p := unsafe { &u8(header.external_data + u64(i64(y) * header.number + i64(x) * 4)) }
			for channel in 0 .. 4 {
				unsafe { p[channel] = u8(math.round(f64(p[channel]) * (1 - coverage))) }
			}
		}
	}
}

fn cg_bitmap_width(context u64) u64 {
	return if context == 0 { u64(0) } else { u64(obj_header(context).frame.width) }
}

fn cg_bitmap_height(context u64) u64 {
	return if context == 0 { u64(0) } else { u64(obj_header(context).frame.height) }
}

fn cg_bitmap_stride(context u64) u64 {
	return if context == 0 { u64(0) } else { u64(obj_header(context).number) }
}

fn cg_bitmap_data(context u64) voidptr {
	return if context == 0 {
		unsafe { nil }
	} else {
		unsafe { voidptr(obj_header(context).external_data) }
	}
}

fn cg_bitmap_bits(context u64) u64 { return if context == 0 { u64(0) } else { u64(8) } }

fn cg_bitmap_pixel_bits(context u64) u64 { return if context == 0 { u64(0) } else { u64(32) } }

fn cg_bitmap_info(context u64) u32 {
	return if context == 0 { u32(0) } else { bitmap_state(context).info }
}

fn cg_bitmap_alpha(context u64) u32 { return cg_bitmap_info(context) & 15 }

fn cg_bitmap_space(context u64) u64 {
	return if context == 0 { u64(0) } else { obj_header(context).fields[0] }
}

fn cg_bitmap_image(context u64) u64 {
	if context == 0 { return 0 }
	source := obj_header(context)
	image := cg_bitmap_create(unsafe { nil }, u64(source.frame.width), u64(source.frame.height), 8, u64(source.number), source.fields[0], bitmap_state(context).info)
	if image == 0 { return 0 }
	objc_set_class(image, ios_runtime.names['VinixCGImage'])
	C.memcpy(cg_bitmap_data(image), cg_bitmap_data(context), usize(source.external_size))
	bitmap_state(image).scale = bitmap_state(context).scale
	return image
}

fn cg_image_provider(image u64) u64 {
	if image == 0 { return 0 }
	mut header := obj_header(image)
	if header.fields[1] == 0 {
		provider := cf_data_create(0, header.external_data, i64(header.external_size))
		objc_set_class(provider, ios_runtime.names['VinixCGDataProvider'])
		header.fields[1] = provider
	}
	return header.fields[1]
}

fn cg_provider_data(provider u64) u64 {
	return if provider == 0 {
		u64(0)
	} else {
		cf_data_create(0, data_pointer(provider), data_length(provider))
	}
}

fn ui_context_stack() &ImageContextStack {
	mut stack := unsafe { &ImageContextStack(C.pthread_getspecific(ios_runtime.graphics_key)) }
	if stack == unsafe { nil } {
		stack = unsafe { &ImageContextStack(C.calloc(1, sizeof(ImageContextStack))) }
		if stack == unsafe { nil } { panic('iOS: cannot allocate image context stack') }
		stack.entries = []ImageContextEntry{}
		stack.entries.flags |= .noslices
		if C.pthread_setspecific(ios_runtime.graphics_key, stack) != 0 {
			panic('iOS: cannot set image context TLS')
		}
	}
	return stack
}

fn ui_context_cleanup(pointer voidptr) {
	if pointer == unsafe { nil } { return }
	mut stack := unsafe { &ImageContextStack(pointer) }
	for entry in stack.entries { objc_release(entry.context) }
	unsafe { stack.entries.free() }
	C.free(stack)
}

fn ui_context_stop() {
	ui_context_cleanup(C.pthread_getspecific(ios_runtime.graphics_key))
	C.pthread_setspecific(ios_runtime.graphics_key, unsafe { nil })
	C.pthread_key_delete(ios_runtime.graphics_key)
}

fn ui_current_context() u64 {
	stack := unsafe { &ImageContextStack(C.pthread_getspecific(ios_runtime.graphics_key)) }
	return if stack == unsafe { nil } || stack.entries.len == 0 {
		u64(0)
	} else {
		stack.entries.last().context
	}
}

fn ui_push_context(context u64) {
	if context != 0 {
		bitmap_state(context)
		ui_context_stack().entries << ImageContextEntry{objc_retain(context), false}
	}
}

fn ui_pop_context() {
	mut stack := ui_context_stack()
	if stack.entries.len != 0 { objc_release(stack.entries.pop().context) }
}

fn ui_begin_image_options(size ObjSize, opaque bool, scale f64) {
	actual_scale := if scale == 0 { f64(1) } else { scale }
	width := math.ceil(size.width * actual_scale)
	height := math.ceil(size.height * actual_scale)
	if !math.is_finite(width) || !math.is_finite(height) || !math.is_finite(actual_scale) || actual_scale <= 0 || width <= 0 || height <= 0 || width > 8192 || height > 8192 {
		panic('iOS: invalid UIKit image context size/scale')
	}
	space := cg_rgb_space()
	context := cg_bitmap_create(unsafe { nil }, u64(width), u64(height), 8, 0, space, if opaque {
		u32(0x2006)
	} else {
		u32(0x2002)
	})
	objc_release(space)
	if context == 0 { panic('iOS: cannot allocate UIKit image context') }
	mut state := bitmap_state(context)
	state.scale = actual_scale
	state.paint.matrix = ObjTransform{actual_scale, 0, 0, -actual_scale, 0, height}
	ui_context_stack().entries << ImageContextEntry{context, true}
}

fn ui_begin_image(size ObjSize) { ui_begin_image_options(size, false, 1) }

fn ui_image_snapshot() u64 {
	stack := unsafe { &ImageContextStack(C.pthread_getspecific(ios_runtime.graphics_key)) }
	if stack == unsafe { nil } { return 0 }
	for i := stack.entries.len - 1; i >= 0; i-- {
		if !stack.entries[i].image { continue }
		image := cg_bitmap_image(stack.entries[i].context)
		if image == 0 { return 0 }
		result := ui_image_from_cg(image, bitmap_state(image).scale)
		objc_release(image)
		return objc_autorelease(result)
	}
	return 0
}

fn ui_end_image() {
	mut stack := ui_context_stack()
	for stack.entries.len != 0 {
		entry := stack.entries.pop()
		objc_release(entry.context)
		if entry.image { break }
	}
}

fn bitmap_symbol(symbol string) ?u64 {
	return match symbol {
		'_UIGraphicsBeginImageContext' { u64(unsafe { voidptr(ui_begin_image) }) }
		'_UIGraphicsBeginImageContextWithOptions' {
			u64(unsafe { voidptr(ui_begin_image_options) })
		}
		'_UIGraphicsEndImageContext' { u64(unsafe { voidptr(ui_end_image) }) }
		'_UIGraphicsGetCurrentContext' { u64(unsafe { voidptr(ui_current_context) }) }
		'_UIGraphicsGetImageFromCurrentImageContext' { u64(unsafe { voidptr(ui_image_snapshot) }) }
		'_UIGraphicsPushContext' { u64(unsafe { voidptr(ui_push_context) }) }
		'_UIGraphicsPopContext' { u64(unsafe { voidptr(ui_pop_context) }) }
		'_CGColorSpaceCreateDeviceRGB' { u64(unsafe { voidptr(cg_rgb_space) }) }
		'_CGColorSpaceRelease', '_CGContextRelease', '_CGImageRelease', '_CGDataProviderRelease' {
			u64(unsafe { voidptr(objc_release) })
		}
		'_CGContextRetain', '_CGImageRetain', '_CGColorSpaceRetain' {
			u64(unsafe { voidptr(objc_retain) })
		}
		'_CGBitmapContextCreate' { u64(unsafe { voidptr(cg_bitmap_create) }) }
		'_CGContextSetFillColorWithColor' { u64(unsafe { voidptr(cg_set_fill) }) }
		'_CGContextSetStrokeColorWithColor' { u64(unsafe { voidptr(cg_set_stroke) }) }
		'_CGContextSetTextPosition' { u64(unsafe { voidptr(cg_text_position) }) }
		'_CGContextSetRGBFillColor' { u64(unsafe { voidptr(cg_rgb_fill_components) }) }
		'_CGContextSetAlpha' { u64(unsafe { voidptr(cg_alpha) }) }
		'_CGContextFillRect' { u64(unsafe { voidptr(cg_fill_rect) }) }
		'_CGContextClearRect' { u64(unsafe { voidptr(cg_clear_rect) }) }
		'_CGContextClipToRect' { u64(unsafe { voidptr(cg_clip) }) }
		'_CGContextGetCTM' { u64(unsafe { voidptr(cg_ctm) }) }
		'_CGContextTranslateCTM' { u64(unsafe { voidptr(cg_translate) }) }
		'_CGContextScaleCTM' { u64(unsafe { voidptr(cg_scale) }) }
		'_CGContextSaveGState' { u64(unsafe { voidptr(cg_save) }) }
		'_CGContextRestoreGState' { u64(unsafe { voidptr(cg_restore) }) }
		'_CGContextSetInterpolationQuality' { u64(unsafe { voidptr(cg_interpolation) }) }
		'_CGBitmapContextGetWidth', '_CGImageGetWidth' { u64(unsafe { voidptr(cg_bitmap_width) }) }
		'_CGBitmapContextGetHeight', '_CGImageGetHeight' {
			u64(unsafe { voidptr(cg_bitmap_height) })
		}
		'_CGBitmapContextGetData' { u64(unsafe { voidptr(cg_bitmap_data) }) }
		'_CGBitmapContextGetBytesPerRow', '_CGImageGetBytesPerRow' {
			u64(unsafe { voidptr(cg_bitmap_stride) })
		}
		'_CGBitmapContextGetBitsPerComponent', '_CGImageGetBitsPerComponent' {
			u64(unsafe { voidptr(cg_bitmap_bits) })
		}
		'_CGBitmapContextGetBitsPerPixel', '_CGImageGetBitsPerPixel' {
			u64(unsafe { voidptr(cg_bitmap_pixel_bits) })
		}
		'_CGBitmapContextGetBitmapInfo', '_CGImageGetBitmapInfo' {
			u64(unsafe { voidptr(cg_bitmap_info) })
		}
		'_CGBitmapContextGetAlphaInfo', '_CGImageGetAlphaInfo' {
			u64(unsafe { voidptr(cg_bitmap_alpha) })
		}
		'_CGBitmapContextGetColorSpace', '_CGImageGetColorSpace' {
			u64(unsafe { voidptr(cg_bitmap_space) })
		}
		'_CGBitmapContextCreateImage' { u64(unsafe { voidptr(cg_bitmap_image) }) }
		'_CGImageGetDataProvider' { u64(unsafe { voidptr(cg_image_provider) }) }
		'_CGDataProviderCopyData' { u64(unsafe { voidptr(cg_provider_data) }) }
		else { return none }
	}
}
