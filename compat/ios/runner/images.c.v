// SPDX-License-Identifier: GPL-2.0-or-later
module main

import math

#include "@VMODROOT/abi/image_config.h"
#include "@VEXEROOT/thirdparty/stb_image/stb_image.h"
#include "@VEXEROOT/thirdparty/stb_image/stb_image_write.h"

fn C.stbi_info_from_memory(&u8, int, &int, &int, &int) int
fn C.stbi_load_from_memory(&u8, int, &int, &int, &int, int) &u8
fn C.stbi_image_free(voidptr)
fn C.stbi_write_png_to_mem(&u8, int, int, int, int, &int) &u8
fn C.stbi_write_jpg_to_func(voidptr, voidptr, int, int, int, &u8, int) int

struct ImageEncoding {
mut:
	bytes []u8
}

fn ui_image_from_cg(image u64, scale f64) u64 {
	if image == 0 { return 0 }
	bitmap_state(image)
	if !math.is_finite(scale) || scale <= 0 { panic('iOS: invalid UIImage scale') }
	object := objc_allocate(ios_runtime.names['UIImage'])
	store_field(object, 0, image)
	obj_header(object).content_scale = scale
	return object
}

fn ui_image_decode(data u64) u64 {
	if data == 0 || data_length(data) <= 0 || data_length(data) > 128 * 1024 * 1024 { return 0 }
	mut width := 0
	mut height := 0
	mut components := 0
	bytes := unsafe { &u8(data_pointer(data)) }
	length := int(data_length(data))
	if C.stbi_info_from_memory(bytes, length, &width, &height, &components) == 0 || width <= 0 || height <= 0 || i64(width) * height > 32 * 1024 * 1024 {
		return 0
	}
	pixels := C.stbi_load_from_memory(bytes, length, &width, &height, &components, 4)
	if pixels == unsafe { nil } { return 0 }
	defer { C.stbi_image_free(pixels) }
	space := cg_rgb_space()
	image := cg_bitmap_create(unsafe { nil }, u64(width), u64(height), 8, u64(width) * 4, space, 1)
	objc_release(space)
	if image == 0 { return 0 }
	objc_set_class(image, ios_runtime.names['VinixCGImage'])
	destination := unsafe { &u8(obj_header(image).external_data) }
	for index := 0; index < width * height * 4; index += 4 {
		alpha := unsafe { u32(pixels[index + 3]) }
		for channel in 0 .. 3 {
			unsafe { destination[index + channel] = u8((u32(pixels[index + channel]) * alpha + 127) / 255) }
		}
		unsafe { destination[index + 3] = u8(alpha) }
	}
	return image
}

fn image_encoding_append(pointer voidptr, bytes voidptr, count int) {
	if count <= 0 { return }
	mut output := unsafe { &ImageEncoding(pointer) }
	if output.bytes.len > 128 * 1024 * 1024 - count {
		panic('iOS: encoded image exceeds supported size')
	}
	unsafe { output.bytes.push_many(bytes, count) }
}

fn ui_image_encode(object u64, quality f64, jpeg bool) u64 {
	if object == 0 { return 0 }
	if !objc_is_kind(object, ios_runtime.names['UIImage']) {
		panic('iOS: image representation requires UIImage')
	}
	image := obj_header(object).fields[0]
	if image == 0 { return 0 }
	width := int(cg_bitmap_width(image))
	height := int(cg_bitmap_height(image))
	components := if jpeg { 3 } else { 4 }
	mut pixels := []u8{len: width * height * components}
	defer { unsafe { pixels.free() } }
	for y in 0 .. height {
		for x in 0 .. width {
			pixel := bitmap_pixel(image, x, y)
			index := (y * width + x) * components
			for channel in 0 .. 3 {
				pixels[index + channel] = u8(if jpeg {
					math.min(u32(255), pixel[channel] + 255 - pixel[3])
				} else if pixel[3] == 0 {
					u32(0)
				} else {
					math.min(u32(255), (pixel[channel] * 255 + pixel[3] / 2) / pixel[3])
				})
			}
			if !jpeg { pixels[index + 3] = u8(pixel[3]) }
		}
	}
	if !jpeg {
		mut size := 0
		encoded := C.stbi_write_png_to_mem(pixels.data, width * 4, width, height, 4, &size)
		if encoded == unsafe { nil } { return 0 }
		defer { C.free(encoded) }
		return objc_autorelease(cf_data_create(0, u64(encoded), size))
	}
	if !math.is_finite(quality) { return 0 }
	mut encoded := unsafe { &ImageEncoding(C.calloc(1, sizeof(ImageEncoding))) }
	if encoded == unsafe { nil } { return 0 }
	encoded.bytes = []u8{cap: 4096}
	encoded.bytes.flags |= .noslices
	defer {
		unsafe { encoded.bytes.free() }
		C.free(encoded)
	}
	result := C.stbi_write_jpg_to_func(unsafe { voidptr(image_encoding_append) }, encoded, width, height, 3, pixels.data, int(math.round(math.max(0, math.min(1, quality)) * 100)))
	if result == 0 { return 0 }
	return objc_autorelease(cf_data_create(0, u64(encoded.bytes.data), encoded.bytes.len))
}

fn ui_png(object u64) u64 { return ui_image_encode(object, 1, false) }

fn ui_jpeg(object u64, quality f64) u64 { return ui_image_encode(object, quality, true) }

fn bitmap_sample(image u64, x f64, y f64, nearest bool) [4]u32 {
	width := int(cg_bitmap_width(image))
	height := int(cg_bitmap_height(image))
	xc := math.max(0, math.min(f64(width - 1), x))
	yc := math.max(0, math.min(f64(height - 1), y))
	if nearest { return bitmap_pixel(image, int(math.floor(xc + 0.5)), int(math.floor(yc + 0.5))) }
	x0 := int(math.floor(xc))
	y0 := int(math.floor(yc))
	x1 := math.min(x0 + 1, width - 1)
	y1 := math.min(y0 + 1, height - 1)
	fx := xc - x0
	fy := yc - y0
	p00 := bitmap_pixel(image, x0, y0)
	p10 := bitmap_pixel(image, x1, y0)
	p01 := bitmap_pixel(image, x0, y1)
	p11 := bitmap_pixel(image, x1, y1)
	mut result := [4]u32{}
	for channel in 0 .. 4 {
		result[channel] = u32(math.round((f64(p00[channel]) * (1 - fx) + f64(p10[channel]) * fx) * (1 - fy) + (f64(p01[channel]) * (1 - fx) + f64(p11[channel]) * fx) * fy))
	}
	return result
}

fn cg_image_pixel_copy(image u64) u64 {
	header := obj_header(image)
	width := u64(header.frame.width)
	height := u64(header.frame.height)
	copy := cg_bitmap_create(unsafe { nil }, width, height, 8, width * 4, header.fields[0], 1)
	if copy == 0 { return 0 }
	objc_set_class(copy, ios_runtime.names['VinixCGImage'])
	bitmap_state(copy).scale = bitmap_state(image).scale
	bytes := unsafe { &u8(obj_header(copy).external_data) }
	for y in 0 .. int(height) {
		for x in 0 .. int(width) {
			pixel := bitmap_pixel(image, x, y)
			for channel in 0 .. 4 {
				unsafe { bytes[(y * int(width) + x) * 4 + channel] = u8(pixel[channel]) }
			}
		}
	}
	return copy
}

fn bitmap_draw_image(context u64, rect ObjRect, image u64, ui bool) {
	if context == 0 || image == 0 || rect.width <= 0 || rect.height <= 0 { return }
	state := bitmap_state(context)
	full := bitmap_rect(context, rect)
	r := bitmap_intersection(full, state.paint.clip)
	if r.width <= 0 || r.height <= 0 { return }
	m := state.paint.matrix
	if m.a == 0 || m.d == 0 { return }
	// A source image may share the destination allocation. Snapshot it before
	// drawing so scaling/overlap never reads pixels already overwritten.
	src := obj_header(image)
	dst := obj_header(context)
	overlap := src.external_data < dst.external_data + dst.external_size && dst.external_data < src.external_data + src.external_size
	source := if overlap { cg_image_pixel_copy(image) } else { objc_retain(image) }
	if source == 0 { return }
	defer { objc_release(source) }
	width := f64(cg_bitmap_width(source))
	height := f64(cg_bitmap_height(source))
	for y := int(math.floor(r.y)); y < int(math.ceil(r.y + r.height)); y++ {
		for x := int(math.floor(r.x)); x < int(math.ceil(r.x + r.width)); x++ {
			ux := ((f64(x) + 0.5 - m.tx) / m.a - rect.x) / rect.width
			uy := ((obj_header(context).frame.height - f64(y) - 0.5 - m.ty) / m.d - rect.y) / rect.height
			coverage := (math.min(f64(x + 1), r.x + r.width) - math.max(f64(x), r.x)) * (math.min(f64(y + 1), r.y + r.height) - math.max(f64(y), r.y))
			pixel := bitmap_sample(source, ux * width - 0.5, (if ui { uy } else { 1 - uy }) * height - 0.5, state.paint.interpolation == 1)
			mut premultiplied := [4]u32{}
			for channel in 0 .. 4 {
				premultiplied[channel] = u32(math.round(f64(pixel[channel]) * state.paint.alpha * coverage))
			}
			bitmap_blend(context, x, y, premultiplied)
		}
	}
}

fn cg_draw_image(context u64, rect ObjRect, image u64) {
	bitmap_draw_image(context, rect, image, false)
}

fn image_selector(object u64, selector string) bool {
	if object in ios_runtime.classes {
		return object == ios_runtime.names['UIImage'] && selector in [
			'imageWithCGImage:',
			'imageWithCGImage:scale:orientation:',
			'imageWithData:',
		]
	}
	if objc_is_kind(object, ios_runtime.names['UIColor']) && selector == 'CGColor' { return true }
	return objc_is_kind(object, ios_runtime.names['UIImage']) && selector in [
		'initWithData:',
		'CGImage',
		'scale',
		'size',
		'imageOrientation',
		'drawInRect:',
	]
}

fn image_dispatch(object u64, selector string, mut frame RegisterFrame) bool {
	if object !in ios_runtime.classes && objc_is_kind(object, ios_runtime.names['UIColor']) && selector == 'CGColor' {
		frame.x[0] = ui_color_cg(object)
		return true
	}
	if object in ios_runtime.classes {
		if object != ios_runtime.names['UIImage'] { return false }
		match selector {
			'imageWithCGImage:', 'imageWithCGImage:scale:orientation:' {
				if selector.contains('orientation') && frame.x[3] != 0 {
					panic('iOS: non-upright UIImage orientation is not implemented')
				}
				frame.x[0] = objc_autorelease(ui_image_from_cg(frame.x[2], if selector == 'imageWithCGImage:' {
					f64(1)
				} else {
					frame_double(frame, 0)
				}))
			}
			'imageWithData:' {
				image := ui_image_decode(frame.x[2])
				frame.x[0] = objc_autorelease(ui_image_from_cg(image, 1))
				objc_release(image)
			}
			else { return false }
		}
		return true
	}
	if !objc_is_kind(object, ios_runtime.names['UIImage']) { return false }
	header := obj_header(object)
	image := header.fields[0]
	match selector {
		'initWithData:' {
			native := ui_image_decode(frame.x[2])
			if native == 0 {
				objc_release(object)
				frame.x[0] = 0
			} else {
				store_field(object, 0, native)
				objc_release(native)
				obj_header(object).content_scale = 1
			}
		}
		'CGImage' { frame.x[0] = image }
		'scale' { frame_float_return(mut frame, 0, header.content_scale) }
		'size' {
			frame_float_return(mut frame, 0, f64(cg_bitmap_width(image)) / header.content_scale)
			frame_float_return(mut frame, 1, f64(cg_bitmap_height(image)) / header.content_scale)
		}
		'imageOrientation' { frame.x[0] = 0 }
		'drawInRect:' { bitmap_draw_image(ui_current_context(), frame_rect(frame), image, true) }
		else { return false }
	}
	return true
}

fn image_symbol(symbol string) ?u64 {
	return match symbol {
		'_UIImagePNGRepresentation' { u64(unsafe { voidptr(ui_png) }) }
		'_UIImageJPEGRepresentation' { u64(unsafe { voidptr(ui_jpeg) }) }
		'_CGContextDrawImage' { u64(unsafe { voidptr(cg_draw_image) }) }
		else { return none }
	}
}
