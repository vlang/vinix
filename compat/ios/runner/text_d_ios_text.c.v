// SPDX-License-Identifier: GPL-2.0-or-later
// The supported CoreText subset uses open fonts and FreeType, with native ARM64
// entry points. It does not load Apple's font or framework implementations.
module main

import math

#include "@VMODROOT/abi/text.h"
fn C.ios_ft_init(&voidptr) i32
fn C.FT_Done_FreeType(voidptr) i32
fn C.ios_ft_open(voidptr, &char, i64, &voidptr) i32
fn C.FT_Done_Face(voidptr) i32
fn C.FT_Get_Postscript_Name(voidptr) &char
fn C.FT_Set_Char_Size(voidptr, i64, i64, u32, u32) i32
fn C.FT_Get_Char_Index(voidptr, u64) u32
fn C.FT_Load_Glyph(voidptr, u32, i32) i32
fn C.ios_ft_render(voidptr) i32
fn C.ios_ft_face_count(voidptr) i64
fn C.ios_ft_traits(voidptr) i64
fn C.ios_ft_family(voidptr) &char
fn C.ios_ft_style(voidptr) &char
fn C.ios_ft_metrics(voidptr, &i64)
fn C.ios_ft_glyph(voidptr, &i64) &u8
fn C.ios_ft_kern(voidptr, u32, u32) i64

struct TextRuntime {
mut:
	library voidptr
	fonts []u64 // Owns registered descriptors; protected by the runtime lock.
}
__global text_runtime = TextRuntime{}

fn text_start() ! {
	if C.ios_ft_init(unsafe { &text_runtime.library }) != 0 { return error('iOS: FreeType initialization failed') }
	text_runtime.fonts = []u64{}
	text_runtime.fonts.flags |= .noslices
}

fn text_stop() {
	for font in text_runtime.fonts { objc_release(font) }
	unsafe { text_runtime.fonts.free() }
	C.FT_Done_FreeType(text_runtime.library)
	text_runtime.library = unsafe { nil }
}

fn text_dispose(object u64) {
	mut header := obj_header(object)
	if header.font_face != unsafe { nil } {
		C.ios_objc_initialize_lock()
		C.FT_Done_Face(header.font_face)
		C.ios_objc_initialize_unlock()
		header.font_face = unsafe { nil }
	}
}

fn ct_descriptors(url u64) u64 {
	if url == 0 || !objc_is_kind(url, ios_runtime.names['NSURL']) { return 0 }
	path := string_text(obj_header(url).fields[0])
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	mut face := unsafe { voidptr(nil) }
	if C.ios_ft_open(text_runtime.library, unsafe { &char(path.str) }, 0, &face) != 0 { return 0 }
	count := C.ios_ft_face_count(face)
	C.FT_Done_Face(face)
	if count < 1 || count > 64 { return 0 }
	array := objc_allocate(ios_runtime.names['NSArray'])
	for index in 0 .. count {
		if C.ios_ft_open(text_runtime.library, unsafe { &char(path.str) }, index, &face) != 0 { objc_release(array); return 0 }
		name := C.FT_Get_Postscript_Name(face)
		if name == unsafe { nil } { C.FT_Done_Face(face); objc_release(array); return 0 }
		descriptor := objc_allocate(ios_runtime.names['VinixCTDescriptor'])
		mut header := obj_header(descriptor)
		store_field(descriptor, 0, make_string(name))
		store_field(descriptor, 1, obj_header(url).fields[0])
		family := C.ios_ft_family(face)
		store_field(descriptor, 2, make_string(if family == unsafe { nil } { name } else { family }))
		style := C.ios_ft_style(face)
		store_field(descriptor, 3, make_string(if style == unsafe { nil } { c'' } else { style }))
		header.number = C.ios_ft_traits(face)
		header.section = index
		array_append(mut obj_header(array), descriptor)
		objc_release(descriptor)
		C.FT_Done_Face(face)
	}
	return array
}

fn ct_register(url u64, scope u32, error_output &u64) bool {
	if scope != 1 || error_output != unsafe { nil } { panic('iOS: only process font registration without CFError output is supported') }
	descriptors := ct_descriptors(url)
	if descriptors == 0 { return false }
	defer { objc_release(descriptors) }
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	for descriptor in obj_header(descriptors).items {
		name := string_text(obj_header(descriptor).fields[0])
		for registered in text_runtime.fonts {
			if string_text(obj_header(registered).fields[0]) == name { return false }
		}
	}
	for descriptor in obj_header(descriptors).items { text_runtime.fonts << objc_retain(descriptor) }
	return true
}

fn ct_descriptor_attribute(descriptor u64, attribute u64) u64 {
	if string_text(attribute) != 'NSFontNameAttribute' { return 0 }
	return objc_retain(obj_header(descriptor).fields[0])
}

fn ct_font_from_descriptor(descriptor u64, size f64) u64 {
	if descriptor == 0 || !math.is_finite(size) || size <= 0 || size > 512 { return 0 }
	header := obj_header(descriptor)
	path := string_text(header.fields[1])
	mut face := unsafe { voidptr(nil) }
	if C.ios_ft_open(text_runtime.library, unsafe { &char(path.str) }, header.section, &face) != 0 { return 0 }
	if C.FT_Set_Char_Size(face, 0, i64(math.round(size * 64)), 72, 72) != 0 { C.FT_Done_Face(face); return 0 }
	font := objc_allocate(ios_runtime.names['VinixCTFont'])
	mut object := obj_header(font)
	object.font_face = face
	object.font_size = size
	store_field(font, 0, descriptor)
	return font
}

fn ct_font_create(name u64, size f64, matrix voidptr) u64 {
	if matrix != unsafe { nil } { panic('iOS: transformed CoreText fonts are unsupported') }
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	for descriptor in text_runtime.fonts {
		if string_text(obj_header(descriptor).fields[0]) == string_text(name) { return ct_font_from_descriptor(descriptor, size) }
	}
	// CoreText also accepts registered family names. Prefer the actual regular
	// face, rather than choosing a light/bold face from registration order.
	mut fallback := u64(0)
	for descriptor in text_runtime.fonts {
		header := obj_header(descriptor)
		if string_text(header.fields[2]) != string_text(name) { continue }
		if string_text(header.fields[3]) in ['Regular', 'Book', 'Roman', 'Normal'] { return ct_font_from_descriptor(descriptor, size) }
		if fallback == 0 { fallback = descriptor }
	}
	if fallback != 0 { return ct_font_from_descriptor(fallback, size) }
	eprintln('iOS: requested font is not registered: ${string_text(name)}')
	return 0
}

fn ct_font_traits(font u64, size f64, matrix voidptr, desired u32, mask u32) u64 {
	if font == 0 || matrix != unsafe { nil } || (desired | mask) & ~u32(3) != 0 { return 0 }
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	base := obj_header(obj_header(font).fields[0])
	traits := (u32(base.number) & ~mask) | (desired & mask)
	if traits == u32(base.number) { return ct_font_from_descriptor(obj_header(font).fields[0], if size == 0 { obj_header(font).font_size } else { size }) }
	for descriptor in text_runtime.fonts {
		candidate := obj_header(descriptor)
		if u32(candidate.number) == traits && string_text(candidate.fields[2]) == string_text(base.fields[2]) {
			return ct_font_from_descriptor(descriptor, if size == 0 { obj_header(font).font_size } else { size })
		}
	}
	return 0
}

fn ct_line_create(attributed u64) u64 {
	if attributed == 0 { return 0 }
	attributes := obj_header(attributed).fields[1]
	if attributes == 0 { return 0 }
	mut font := u64(0)
	for index, key in obj_header(attributes).keys {
		if string_text(key) == 'NSFont' { font = obj_header(attributes).items[index]; break }
	}
	if font == 0 || !objc_is_kind(font, ios_runtime.names['VinixCTFont']) { return 0 }
	line := objc_allocate(ios_runtime.names['VinixCTLine'])
	store_field(line, 0, obj_header(attributed).fields[0])
	store_field(line, 1, font)
	mut header := obj_header(line)
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	face := obj_header(font).font_face
	mut metrics := [3]i64{}
	C.ios_ft_metrics(face, &metrics[0])
	header.frame.x = f64(metrics[0]) / 64
	header.frame.y = -f64(metrics[1]) / 64
	header.frame.height = math.max(f64(metrics[2]) / 64 - header.frame.x - header.frame.y, 0)
	header.frame.width = text_glyphs(line, 0)
	return line
}

fn ct_line_bounds(line u64, ascent &f64, descent &f64, leading &f64) f64 {
	header := obj_header(line)
	unsafe {
		if ascent != nil { *ascent = header.frame.x }
		if descent != nil { *descent = header.frame.y }
		if leading != nil { *leading = header.frame.height }
	}
	return header.frame.width
}

fn text_glyphs(line u64, context u64) f64 {
	face := obj_header(obj_header(line).fields[1]).font_face
	mut pen := i64(0)
	mut previous := u32(0)
	runes := string_text(obj_header(line).fields[0]).runes()
	defer { unsafe { runes.free() } }
	for code in runes {
		glyph := C.FT_Get_Char_Index(face, u64(code))
		pen += C.ios_ft_kern(face, previous, glyph)
		if C.FT_Load_Glyph(face, glyph, 0) != 0 { panic('iOS: FreeType glyph loading failed') }
		mut values := [7]i64{}
		if context != 0 && C.ios_ft_render(face) != 0 { panic('iOS: FreeType glyph rasterization failed') }
		bitmap := C.ios_ft_glyph(face, &values[0])
		if context != 0 && values[3] > 0 && values[4] > 0 {
			if values[6] != 2 { panic('iOS: only grayscale FreeType glyphs are supported') }
			text_composite(context, bitmap, values, f64(pen) / 64)
		}
		pen += values[0]
		previous = glyph
	}
	return f64(pen) / 64
}

fn text_composite(context u64, bitmap &u8, glyph [7]i64, pen f64) {
	header := obj_header(context)
	state := bitmap_state(context)
	if state.paint.matrix != ObjTransform{1, 0, 0, 1, 0, 0} { panic('iOS: transformed CoreText bitmap drawing is not implemented') }
	if header.frame.x + pen < -1024 || header.frame.x + pen > header.frame.width + 1024 || header.frame.y < -1024 || header.frame.y > header.frame.height + 1024 { return }
	x0 := i64(math.floor(header.frame.x + pen)) + glyph[1]
	y0 := i64(header.frame.height) - i64(math.floor(header.frame.y)) - glyph[2]
	for row in 0 .. glyph[4] {
		y := y0 + row
		if y < 0 || y >= i64(header.frame.height) { continue }
		for column in 0 .. glyph[3] {
			x := x0 + column
			if x < 0 || x >= i64(header.frame.width) { continue }
			clip := state.paint.clip
			clip_coverage := math.max(0, math.min(f64(x + 1), clip.x + clip.width) - math.max(f64(x), clip.x)) * math.max(0, math.min(f64(y + 1), clip.y + clip.height) - math.max(f64(y), clip.y))
			if clip_coverage == 0 { continue }
			source_row := if glyph[5] < 0 { glyph[4] - 1 - row } else { row }
			coverage := unsafe { bitmap[source_row * i64(math.abs(glyph[5])) + column] }
			alpha := u32(math.round(f64(coverage) * header.real_number * state.paint.alpha * clip_coverage))
			if alpha == 0 { continue }
			bitmap_blend(context, int(x), int(y), [(((header.color >> 16) & 255) * alpha + 127) / 255, (((header.color >> 8) & 255) * alpha + 127) / 255, ((header.color & 255) * alpha + 127) / 255, alpha]!)
		}
	}
}

fn ct_line_draw(line u64, context u64) {
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	text_glyphs(line, context)
}

fn text_symbol(symbol string) ?u64 {
	return match symbol {
		'_CTFontManagerCreateFontDescriptorsFromURL' { u64(unsafe { voidptr(ct_descriptors) }) }
		'_CTFontManagerRegisterFontsForURL' { u64(unsafe { voidptr(ct_register) }) }
		'_CTFontDescriptorCopyAttribute' { u64(unsafe { voidptr(ct_descriptor_attribute) }) }
		'_CTFontCreateWithName' { u64(unsafe { voidptr(ct_font_create) }) }
		'_CTFontCreateCopyWithSymbolicTraits' { u64(unsafe { voidptr(ct_font_traits) }) }
		'_CTLineCreateWithAttributedString' { u64(unsafe { voidptr(ct_line_create) }) }
		'_CTLineGetTypographicBounds' { u64(unsafe { voidptr(ct_line_bounds) }) }
		'_CTLineDraw' { u64(unsafe { voidptr(ct_line_draw) }) }
		else { return none }
	}
}
