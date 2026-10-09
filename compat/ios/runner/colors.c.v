// SPDX-License-Identifier: GPL-2.0-or-later
// Owned RGB/gray colors with full CGFloat components. Rasterization alone
// quantizes values to bytes; equality and borrowed components keep precision.
module main

import math

fn cg_space_create(profile i64) u64 {
	space := objc_allocate(ios_runtime.names['VinixCGColorSpace'])
	mut header := obj_header(space)
	header.number = profile // 1/2 device RGB/gray; 3/4 UIKit extended RGB/gray.
	return space
}

fn cg_gray_space() u64 { return cg_space_create(2) }

fn cg_space_components(space u64) u64 {
	if space == 0 { return 0 }
	profile := obj_header(space).number
	return if profile in [i64(2), 4] { u64(1) } else { u64(3) }
}

fn cg_space_model(space u64) i32 {
	if space == 0 { return -1 }
	return if cg_space_components(space) == 1 { i32(0) } else { i32(1) }
}

fn color_components_set(object u64, components &f64, count int, extended bool) {
	mut header := obj_header(object)
	header.data = []u8{len: count * 8}
	for index in 0 .. count {
		value := unsafe { components[index] }
		if !math.is_finite(value) { panic('iOS: non-finite color component is not implemented') }
		unsafe { *(&f64(u64(header.data.data) + u64(index) * 8)) = if extended && index != count - 1 { value } else { math.clamp(value, 0.0, 1.0) } }
	}
	values := unsafe { &f64(header.data.data) }
	red := unsafe { values[0] }
	green := if count == 2 { red } else { unsafe { values[1] } }
	blue := if count == 2 { red } else { unsafe { values[2] } }
	header.color = bitmap_component(red) << 16 | bitmap_component(green) << 8 | bitmap_component(blue)
	header.real_number = unsafe { values[count - 1] }
	header.is_real = true
}

fn cg_color_create(space u64, components &f64) u64 {
	if space == 0 || components == unsafe { nil } { return 0 }
	if !objc_is_kind(space, ios_runtime.names['VinixCGColorSpace']) { return 0 }
	count := int(cg_space_components(space)) + 1
	color := objc_allocate(ios_runtime.names['VinixCGColor'])
	color_components_set(color, components, count, obj_header(space).number in [i64(3), 4])
	mut header := obj_header(color)
	store_field(color, 0, space)
	header.number = obj_header(space).number
	return color
}

fn cg_color_components(color u64) &f64 {
	if color == 0 { return unsafe { nil } }
	return unsafe { &f64(obj_header(color).data.data) }
}

fn cg_color_count(color u64) u64 { return if color == 0 { u64(0) } else { u64(obj_header(color).data.len / 8) } }

fn cg_color_space(color u64) u64 { return if color == 0 { u64(0) } else { obj_header(color).fields[0] } }

fn cg_color_alpha(color u64) f64 { return if color == 0 { f64(0) } else { obj_header(color).real_number } }

fn cg_color_equal(left u64, right u64) bool {
	if left == right { return true }
	if left == 0 || right == 0 { return false }
	a := obj_header(left)
	b := obj_header(right)
	if a.number != b.number || a.data.len != b.data.len { return false }
	for index in 0 .. a.data.len / 8 {
		if unsafe { (&f64(a.data.data))[index] != (&f64(b.data.data))[index] } { return false }
	}
	return true
}

fn cg_color_copy_alpha(color u64, alpha f64) u64 {
	if color == 0 { return 0 }
	mut values := [4]f64{}
	count := int(cg_color_count(color))
	for index in 0 .. count { values[index] = unsafe { cg_color_components(color)[index] } }
	values[count - 1] = alpha
	return cg_color_create(cg_color_space(color), unsafe { &values[0] })
}

fn ui_color_cg(object u64) u64 {
	mut header := obj_header(object)
	if header.fields[8] != 0 { return header.fields[8] }
	profile := if header.number in [i64(3), 4] { header.number } else { i64(3) }
	space := cg_space_create(profile)
	defer { objc_release(space) }
	mut values := [f64(header.color >> 16 & 255) / 255, f64(header.color >> 8 & 255) / 255, f64(header.color & 255) / 255, if header.is_real { header.real_number } else { f64(1) }]!
	if header.data.len != 0 {
		count := header.data.len / 8
		for index in 0 .. count { values[index] = unsafe { (&f64(header.data.data))[index] } }
	}
	header.fields[8] = cg_color_create(space, unsafe { &values[0] })
	return header.fields[8]
}

fn cg_fill_color_space(context u64, space u64) {
	if context == 0 || space == 0 { return }
	mut state := bitmap_state(context)
	state.paint.fill_components = u32(cg_space_components(space))
}

fn cg_fill_color(context u64, components &f64) {
	if context == 0 || components == unsafe { nil } { return }
	state := bitmap_state(context)
	if state.paint.fill_components == 1 {
		unsafe { cg_rgb_fill(context, components[0], components[0], components[0], components[1]) }
	} else {
		unsafe { cg_rgb_fill(context, components[0], components[1], components[2], components[3]) }
	}
}

fn cg_flush(context u64) { if context != 0 { bitmap_state(context) } } // Bitmap writes are synchronous.

fn cg_blend_mode(context u64, mode u32) {
	if context == 0 { return }
	bitmap_state(context)
	if mode != 0 { panic('iOS: bitmap blend mode is not implemented') }
}

fn color_symbol(symbol string) ?u64 {
	address := match symbol {
		'_CGColorCreate' { unsafe { voidptr(cg_color_create) } }
		'_CGColorCreateCopyWithAlpha' { unsafe { voidptr(cg_color_copy_alpha) } }
		'_CGColorEqualToColor' { unsafe { voidptr(cg_color_equal) } }
		'_CGColorGetComponents' { unsafe { voidptr(cg_color_components) } }
		'_CGColorGetNumberOfComponents' { unsafe { voidptr(cg_color_count) } }
		'_CGColorGetColorSpace' { unsafe { voidptr(cg_color_space) } }
		'_CGColorGetAlpha' { unsafe { voidptr(cg_color_alpha) } }
		'_CGColorRetain' { unsafe { voidptr(objc_retain) } }
		'_CGColorRelease' { unsafe { voidptr(objc_release) } }
		'_CGColorSpaceCreateDeviceGray' { unsafe { voidptr(cg_gray_space) } }
		'_CGColorSpaceGetNumberOfComponents' { unsafe { voidptr(cg_space_components) } }
		'_CGColorSpaceGetModel' { unsafe { voidptr(cg_space_model) } }
		'_CGContextSetFillColorSpace' { unsafe { voidptr(cg_fill_color_space) } }
		'_CGContextSetFillColor' { unsafe { voidptr(cg_fill_color) } }
		'_CGContextSetBlendMode' { unsafe { voidptr(cg_blend_mode) } }
		'_CGContextFlush' { unsafe { voidptr(cg_flush) } }
		else { return none }
	}
	return u64(address)
}
